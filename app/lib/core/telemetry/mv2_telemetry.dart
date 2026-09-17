import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
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
  static Future<void> start() async {
    FlutterError.onError = _onFlutterError;
    PlatformDispatcher.instance.onError = _onPlatformError;

    if (!await ensureFirebase()) return;

    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
      _ready = true;
      unawaited(FirebaseAnalytics.instance.logAppOpen());
    } catch (error) {
      // Firebase is up but the telemetry products are not; the app still runs.
      debugPrint('MV2: telemetry unavailable: $error');
    }
  }

  /// Records a handled, non-fatal failure (e.g. a write the server rejected).
  static void recordNonFatal(Object error, StackTrace stack, {String? reason}) {
    if (!_ready) return;
    unawaited(
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
        fatal: false,
      ),
    );
  }

  /// Attaches the current theme context as Crashlytics custom keys, so a
  /// "颜色不对" report can be read against what the app actually applied
  /// (in-app preference × system brightness).
  static void setThemeContext({required String colorMode}) {
    if (!_ready) return;
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    FirebaseCrashlytics.instance.setCustomKey('colorMode', colorMode);
    FirebaseCrashlytics.instance.setCustomKey(
      'systemBrightness',
      brightness.name,
    );
  }

  static void _onFlutterError(FlutterErrorDetails details) {
    // Keep the red screen / console output in debug.
    FlutterError.presentError(details);
    if (!_ready) return;
    unawaited(FirebaseCrashlytics.instance.recordFlutterFatalError(details));
  }

  static bool _onPlatformError(Object error, StackTrace stack) {
    if (_ready) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
      );
    }
    return true;
  }
}
