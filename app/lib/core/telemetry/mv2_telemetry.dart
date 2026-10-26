import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart' show WidgetsBinding;

/// Firebase crash reporting + analytics.
///
/// Boots lazily and tolerates a missing config: `flutter test`, desktop runs
/// without a macOS `GoogleService-Info.plist`, and any build where the plist has
/// not been added to the target all land in the "unavailable" branch instead of
/// taking the app down. The error handlers are installed **synchronously** so a
/// crash during the very first frames is still reported once Firebase is up.
abstract final class Mv2Telemetry {
  static bool _ready = false;
  static Future<void>? _starting;
  static Timer? _retry;
  static int _attempts = 0;
  static bool _flushing = false;
  static final _pending =
      <({Object error, StackTrace stack, String reason, bool fatal})>[];
  static final _recent = <String, DateTime>{};
  static String _screen = 'startup';

  /// Only route templates and operation names belong here, never user text.
  static void setScreen(String screen) {
    _screen = screen;
    if (_ready) unawaited(_sdkLog('screen=$screen'));
  }

  static Future<void> _sdkLog(String message) async {
    try {
      await FirebaseCrashlytics.instance.log(message);
    } catch (_) {}
  }

  /// Single-flight Firebase boot shared by telemetry and the push gateway, so
  /// two callers cannot race into `initializeApp()` and have one of them see
  /// "duplicate-app".
  static Future<bool>? _boot;

  /// True once Firebase is up and Crashlytics collection is enabled.
  static bool get isReady => _ready;

  /// Ensures Firebase is initialized; `true` when an app is available.
  ///
  /// Safe to call from anywhere and any number of times.
  static Future<bool> ensureFirebase() {
    return _boot ??= _initialize();
  }

  static Future<bool> _initialize() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      return true;
    } catch (error) {
      // No config / unsupported platform.
      debugPrint('MV2: Firebase unavailable: $error');
      return false;
    }
  }

  /// Installs the error handlers and boots Firebase in the background.
  ///
  /// Never awaited by `main()`: blocking the first frame on a network-capable
  /// SDK would eat the cold-start budget (`docs/13` Phase 6 targets ≤1.5s).
  static Future<void> start() => _starting ??= _start().whenComplete(() {
    _starting = null;
  });

  static Future<void> _start() async {
    FlutterError.onError = _onFlutterError;
    PlatformDispatcher.instance.onError = _onPlatformError;

    if (_ready) return;
    _attempts++;
    if (!await ensureFirebase()) {
      _boot = null;
      _scheduleRetry();
      return;
    }

    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      _ready = true;
      unawaited(_flush());
      // Analytics availability must not disable Crashlytics.
      try {
        await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
        await FirebaseAnalytics.instance.logAppOpen();
      } catch (error, stack) {
        recordNonFatal(error, stack, reason: 'telemetry.analytics.initialize');
      }
    } catch (error) {
      // Firebase is up but the telemetry products are not; the app still runs.
      debugPrint('MV2: telemetry unavailable: ${error.runtimeType}');
      _scheduleRetry();
    }
  }

  static void _scheduleRetry() {
    if (_attempts >= 4 || _retry?.isActive == true) return;
    _retry = Timer(Duration(seconds: 5 * _attempts), () => unawaited(start()));
  }

  /// Bounded startup queue; repeated failures are grouped to avoid burying
  /// actionable reports. Never attach drafts, credentials or response bodies.
  static void recordNonFatal(Object error, StackTrace stack, {String? reason}) {
    _record(error, stack, reason: reason ?? 'handled', fatal: false);
  }

  static String _safe(String value) => value
      .replaceAll(RegExp(r'https?://[^\s)]+'), '[url]')
      .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'), '[email]')
      .replaceAll(RegExp(r'(?:Bearer\s+|APA91)[A-Za-z0-9_./+:-]+'), '[token]');

  static void _record(
    Object error,
    StackTrace stack, {
    required String reason,
    required bool fatal,
  }) {
    final operation = _safe(reason).replaceAll(RegExp(r'\b\d+\b'), ':id');
    final code = error is PlatformException ? _safe(error.code) : '';
    final nativeAbi =
        error is PlatformException &&
        error.toString().contains('NoSuchMethodError');
    final signature =
        '${error.runtimeType}${code.isEmpty ? '' : ':$code'}${nativeAbi ? ':NoSuchMethodError' : ''}';
    final key = '$signature:$operation';
    final now = DateTime.now();
    if (!fatal &&
        _recent[key] != null &&
        now.difference(_recent[key]!) < const Duration(minutes: 1)) {
      return;
    }
    _recent.removeWhere(
      (_, time) => now.difference(time) > const Duration(minutes: 1),
    );
    _recent[key] = now;
    if (_pending.length >= 32) _pending.removeAt(0);
    // Exception messages may contain request data; preserve type, operation and
    // stack instead. Human-readable Failure categories are in the operation.
    _pending.add((
      error: signature,
      stack: stack,
      reason: '$operation | screen=$_screen',
      fatal: fatal,
    ));
    if (_ready) unawaited(_flush());
  }

  static Future<void> _flush() async {
    if (_flushing || !_ready) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty) {
        final report = _pending.first;
        try {
          await FirebaseCrashlytics.instance.recordError(
            report.error,
            report.stack,
            reason: report.reason,
            fatal: report.fatal,
          );
          _pending.remove(report);
        } catch (_) {
          // Never recursively report SDK errors or create unhandled Futures.
          _retry?.cancel();
          _retry = Timer(
            const Duration(seconds: 30),
            () => unawaited(_flush()),
          );
          break;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// Attaches the current theme context as Crashlytics custom keys, so a
  /// "颜色不对" report can be read against what the app actually applied
  /// (in-app preference × system brightness).
  static void setThemeContext({required String colorMode}) {
    if (!_ready) return;
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    unawaited(_setThemeKeys(colorMode, brightness.name));
  }

  static Future<void> _setThemeKeys(String colorMode, String brightness) async {
    try {
      await FirebaseCrashlytics.instance.setCustomKey('colorMode', colorMode);
      await FirebaseCrashlytics.instance.setCustomKey(
        'systemBrightness',
        brightness,
      );
    } catch (_) {}
  }

  static void _onFlutterError(FlutterErrorDetails details) {
    // Keep the red screen / console output in debug.
    FlutterError.presentError(details);
    _record(
      details.exception,
      details.stack ?? StackTrace.current,
      reason: 'flutter.framework',
      fatal: false,
    );
  }

  static bool _onPlatformError(Object error, StackTrace stack) {
    _record(error, stack, reason: 'dart.unhandled', fatal: true);
    return true;
  }
}
