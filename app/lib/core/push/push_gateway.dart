import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../telemetry/mv2_telemetry.dart';

/// The push SDK surface MV2 depends on, behind one interface.
///
/// Everything platform- and plugin-specific lives in [FirebasePushGateway]; the
/// service and the UI only ever touch this seam, which keeps Firebase out of
/// widget tests (the plugin throws `MissingPluginException` there) and lets
/// desktop/web runs degrade to "push unavailable" instead of crashing.
abstract interface class Mv2PushGateway {
  /// Initialises the SDK. Never throws: a missing `google-services.json` /
  /// `GoogleService-Info.plist` just leaves push unavailable.
  Future<void> initialize();

  /// Whether [initialize] found a usable Firebase app.
  bool get isAvailable;

  /// Asks the OS for notification permission. Returns `false` when denied or
  /// when push is unavailable.
  Future<bool> requestPermission();

  /// The current FCM registration token, or `null` when unavailable/denied.
  Future<String?> token();

  /// Emits on every FCM token rotation.
  Stream<String> tokenRefreshes();

  /// Notification taps that opened or resumed the app.
  Stream<Map<String, Object?>> opened();

  /// The notification that cold-started the app, if any. Call once, early.
  Future<Map<String, Object?>?> initialOpened();

  /// Messages that arrive while the app is in the foreground.
  Stream<Map<String, Object?>> foreground();
}

/// [Mv2PushGateway] backed by `firebase_messaging`.
class FirebasePushGateway implements Mv2PushGateway {
  FirebasePushGateway([this._messaging]);

  final FirebaseMessaging? _messaging;

  bool _available = false;

  @override
  bool get isAvailable => _available;

  FirebaseMessaging get _fcm => _messaging ?? FirebaseMessaging.instance;

  @override
  Future<void> initialize() async {
    // Shared with telemetry so the two callers cannot race `initializeApp()`.
    _available = await Mv2Telemetry.ensureFirebase();
  }

  @override
  Future<bool> requestPermission() async {
    if (!_available) return false;
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus != AuthorizationStatus.denied;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> token() async {
    if (!_available) return null;
    try {
      return await _fcm.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> tokenRefreshes() =>
      _available ? _fcm.onTokenRefresh : const Stream<String>.empty();

  @override
  Stream<Map<String, Object?>> opened() => _available
      ? FirebaseMessaging.onMessageOpenedApp.map(_data)
      : const Stream<Map<String, Object?>>.empty();

  @override
  Future<Map<String, Object?>?> initialOpened() async {
    if (!_available) return null;
    try {
      final message = await _fcm.getInitialMessage();
      return message == null ? null : _data(message);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Map<String, Object?>> foreground() => _available
      ? FirebaseMessaging.onMessage.map(_data)
      : const Stream<Map<String, Object?>>.empty();

  static Map<String, Object?> _data(RemoteMessage message) =>
      Map<String, Object?>.from(message.data);
}
