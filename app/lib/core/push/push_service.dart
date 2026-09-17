import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../telemetry/mv2_analytics.dart';
import 'push_gateway.dart';

/// `POST`s a registration body to the worker; returns whether it was accepted.
typedef PushRegisterPost =
    Future<bool> Function(String url, Map<String, Object?> body);

/// One `register()` attempt's ending — reported as the `push_register`
/// analytics result. 只记枚举,不记 token / feedUrl(PII)。
enum PushRegisterOutcome {
  /// Worker accepted the payload (or the pair was already stored).
  registered,

  /// Nothing to do: `(token, feedUrl)` identical to the last registration.
  unchanged,

  /// 推送通知 setting is off.
  disabled,

  /// Gateway/SDK unusable on this platform (no config, ohos shim, …).
  unavailable,

  /// The OS permission prompt was denied.
  permissionDenied,

  /// Account has never opened `/notifications`, so there is no feed URL yet.
  noFeedUrl,

  /// FCM handed back an empty token.
  noToken,

  /// Worker rejected the POST, or something threw.
  failed,
}

/// Registers this device with the MV2 push worker.
///
/// The worker (`cloudflare/`, `docs/12` §8) owns the polling: it re-reads each
/// registered account's notification Atom feed every 15 minutes and pushes the
/// new items through FCM. The client's only job is to hand it a device token
/// plus the account's private feed URL.
///
/// Registration is deliberately lazy and idempotent:
///
/// * the feed URL only exists on `/notifications`, so the first successful
///   visit to that page is what enrols the device (same trigger the legacy MAUI
///   client used);
/// * the pair `(token, feedUrl)` is cached, so reopening the page, rotating the
///   FCM token and cold starts do not re-POST the same payload;
/// * every failure path returns quietly — push must never block the UI.
class Mv2PushService {
  Mv2PushService({
    required Mv2PushGateway pushGateway,
    bool Function()? isEnabled,
    PushRegisterPost? post,
    SharedPreferences? prefs,
  }) : _gateway = pushGateway,
       _isEnabled = isEnabled ?? _alwaysEnabled,
       _post = post ?? _postWithDio,
       _preferences = prefs;

  /// Worker base URL. Override per environment with
  /// `--dart-define=MV2_PUSH_WORKER_URL=…` (e.g. a `wrangler dev` instance).
  static const String workerBaseUrl = String.fromEnvironment(
    'MV2_PUSH_WORKER_URL',
    defaultValue: 'https://v2ex-push-service.rwecho.workers.dev',
  );

  static const String _kFeedUrl = 'mv2.push.feedUrl';
  static const String _kRegisteredToken = 'mv2.push.registeredToken';
  static const String _kRegisteredFeed = 'mv2.push.registeredFeedUrl';

  final Mv2PushGateway _gateway;
  final bool Function() _isEnabled;
  final PushRegisterPost _post;
  SharedPreferences? _preferences;

  final StreamController<Map<String, Object?>> _opened =
      StreamController<Map<String, Object?>>.broadcast();
  final StreamController<Map<String, Object?>> _foreground =
      StreamController<Map<String, Object?>>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  Future<void>? _starting;
  /// Notification taps (cold start included) as raw FCM `data` maps — feed
  /// them to `Mv2PushPayload.routeFor`.
  Stream<Map<String, Object?>> get openedPayloads => _opened.stream;

  /// Messages that arrived while the app was in the foreground. The system does
  /// not show those on its own, so this is what refreshes the unread badge.
  Stream<Map<String, Object?>> get foregroundMessages => _foreground.stream;

  /// The feed URL of the last successful registration, if any.
  Future<String?> cachedFeedUrl() async =>
      _validFeed((await _prefs()).getString(_kFeedUrl));

  /// Wires the SDK up once per process. Safe to call from several widgets.
  ///
  /// The in-flight future is shared: `register` awaits the same initialisation
  /// the shell kicked off, so a notification page opened during startup cannot
  /// observe "not available" and skip registration.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    await _gateway.initialize();
    if (!_gateway.isAvailable) return;

    _subscriptions.add(
      _gateway.tokenRefreshes().listen((_) => unawaited(register())),
    );
    _subscriptions.add(_gateway.opened().listen(_opened.add));
    _subscriptions.add(_gateway.foreground().listen(_foreground.add));

    // A tap that cold-started the app fires before anyone was listening.
    final initial = await _gateway.initialOpened();
    if (initial != null && !_opened.isClosed) _opened.add(initial);
  }

  /// Enrols this device, reusing the remembered feed URL when [feedUrl] is not
  /// supplied (cold start, token rotation).
  ///
  /// Every return path lands on exactly one [PushRegisterOutcome], which is
  /// both the analytics payload and the caller-visible result.
  Future<PushRegisterOutcome> register({String? feedUrl}) async {
    try {
      if (!_isEnabled()) return _done(PushRegisterOutcome.disabled);
      await start();
      if (!_gateway.isAvailable) return _done(PushRegisterOutcome.unavailable);

      final prefs = await _prefs();
      final feed = _validFeed(feedUrl) ?? _validFeed(prefs.getString(_kFeedUrl));
      // No feed URL yet: the account has never opened /notifications.
      if (feed == null) return _done(PushRegisterOutcome.noFeedUrl);

      if (feedUrl != null) await prefs.setString(_kFeedUrl, feed);

      // Asked here rather than at launch: by the time we know the account has
      // notifications, the prompt has context. A denial is final until the user
      // changes it in system settings.
      if (!await _gateway.requestPermission()) {
        return _done(PushRegisterOutcome.permissionDenied);
      }

      final token = await _gateway.token();
      if (token == null || token.isEmpty) {
        return _done(PushRegisterOutcome.noToken);
      }

      final unchanged =
          prefs.getString(_kRegisteredToken) == token &&
          prefs.getString(_kRegisteredFeed) == feed;
      if (unchanged) return _done(PushRegisterOutcome.unchanged);

      final accepted = await _post('$workerBaseUrl/register', <String, Object?>{
        'feedUrl': feed,
        'fcmToken': token,
        'deviceType': _deviceType(),
      });
      if (!accepted) return _done(PushRegisterOutcome.failed);

      await prefs.setString(_kRegisteredToken, token);
      await prefs.setString(_kRegisteredFeed, feed);
      return _done(PushRegisterOutcome.registered);
    } catch (_) {
      // Push is best-effort: a network/plugin failure must not surface as a
      // broken notifications page.
      return _done(PushRegisterOutcome.failed);
    }
  }

  /// Single exit funnel so the analytics event fires once per attempt.
  PushRegisterOutcome _done(PushRegisterOutcome outcome) {
    Mv2Analytics.logPushRegister(result: outcome.name);
    return outcome;
  }

  /// Drops the remembered feed URL (used when the account signs out).
  Future<void> forgetFeedUrl() async {
    await (await _prefs()).remove(_kFeedUrl);
  }

  /// Stops server-side polling for this device (推送通知 switched off).
  ///
  /// Best-effort and additive: older worker deployments answer 404 for
  /// `/unregister`, in which case the local state is still cleared but the
  /// worker keeps polling until it is redeployed.
  Future<void> unregister() async {
    try {
      final prefs = await _prefs();
      final token =
          prefs.getString(_kRegisteredToken) ?? await _gateway.token();
      if (token == null || token.isEmpty) return;

      await _post('$workerBaseUrl/unregister', <String, Object?>{
        'fcmToken': token,
      });
      await prefs.remove(_kRegisteredToken);
      await prefs.remove(_kRegisteredFeed);
      await prefs.remove(_kFeedUrl);
    } catch (_) {
      // Same contract as register: never surface a push failure in the UI.
    }
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _opened.close();
    await _foreground.close();
  }

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  static bool _alwaysEnabled() => true;

  /// The worker rejects anything that is not a v2ex.com feed; mirror that here
  /// so a malformed `input.sll` never reaches it (or the KV store).
  static String? _validFeed(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.host.endsWith('v2ex.com')) return null;
    if (!uri.path.contains('/feed/')) return null;
    return value;
  }

  static String _deviceType() => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.android => 'Android',
    final other => other.name,
  };

  static Future<bool> _postWithDio(
    String url,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      ).post<Object?>(url, data: body);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
