/// HarmonyOS (ohos) shim for `firebase_core`.
///
/// Google Firebase has no HarmonyOS SDK, so the ohos variant cannot use FCM.
/// HarmonyOS push is HMS Push Kit, which the publisher still has to wire up
/// (see app-ohos/README.md).
///
/// [Firebase.initializeApp] always throws. `FirebasePushGateway.initialize()`
/// already catches every failure and sets `isAvailable = false`, so the whole
/// push stack degrades to "unavailable" with no UI changes and no crashed
/// startup.
class Firebase {
  Firebase._();

  static const List<FirebaseApp> apps = <FirebaseApp>[];

  static Future<FirebaseApp> initializeApp({
    String? name,
    Object? options,
  }) async {
    throw UnsupportedError(
      'Firebase (FCM) is unavailable on HarmonyOS; use HMS Push Kit instead.',
    );
  }
}

class FirebaseApp {
  const FirebaseApp(this.name);

  final String name;
}
