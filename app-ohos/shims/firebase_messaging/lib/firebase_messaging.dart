/// HarmonyOS (ohos) shim for `firebase_messaging`.
///
/// Keeps the exact Dart surface `FirebasePushGateway` uses so
/// `lib/core/push/push_gateway.dart` is byte-identical to mainline. Every
/// method that matters is gated by `FirebasePushGateway._available`, which can
/// never become `true` because the `firebase_core` shim's
/// `Firebase.initializeApp()` always throws. The members below therefore only
/// have to *compile* and to be safe if ever reached.
class FirebaseMessaging {
  FirebaseMessaging._();

  static final FirebaseMessaging instance = FirebaseMessaging._();

  static const Stream<RemoteMessage> onMessage = Stream<RemoteMessage>.empty();
  static const Stream<RemoteMessage> onMessageOpenedApp =
      Stream<RemoteMessage>.empty();

  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  Future<AuthorizationSettings> requestPermission({
    bool alert = false,
    bool badge = false,
    bool sound = false,
    bool provisional = false,
    bool criticalAlert = false,
  }) async {
    return const AuthorizationSettings(AuthorizationStatus.denied);
  }

  Future<String?> getToken({String? vapidKey}) async => null;

  Future<RemoteMessage?> getInitialMessage() async => null;
}

/// `firebase_messaging` calls this `NotificationSettings`; MV2 only reads
/// `authorizationStatus`.
class AuthorizationSettings {
  const AuthorizationSettings(this.authorizationStatus);

  final AuthorizationStatus authorizationStatus;
}

enum AuthorizationStatus { notDetermined, denied, authorized, provisional }

class RemoteMessage {
  const RemoteMessage({this.data = const <String, dynamic>{}});

  final Map<String, dynamic> data;
}
