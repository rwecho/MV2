import 'package:shared_preferences/shared_preferences.dart';

/// HarmonyOS (ohos) shim for `flutter_secure_storage`.
///
/// The real package has no HarmonyOS implementation, and the only community
/// port on pub.dev (`flutter_secure_storage_ohos` 1.0.0) predates Dart 3 and
/// cannot resolve. This shim preserves the exact API surface the app uses
/// (`read` / `write` / `delete`, all keyed by `String`) so
/// `SecureCookieStorage` and `AuthStore` compile and run unchanged.
///
/// [securityDegraded] is `true` and is surfaced in the settings/about page copy
/// via the README — values live in `SharedPreferences`, i.e. plain app-sandbox
/// storage, not a keystore.
class FlutterSecureStorage {
  const FlutterSecureStorage({
    // Accepted and ignored so a mainline call site that passes options still
    // compiles against the shim.
    Object? aOptions,
    Object? iOptions,
    Object? lOptions,
    Object? mOptions,
    Object? wOptions,
    Object? webOptions,
  });

  /// Always `true` on the ohos variant: storage is *not* keystore-backed.
  static const bool securityDegraded = true;

  static const String _namespace = 'mv2.secure_shim.';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> read({required String key}) async {
    try {
      return (await _prefs).getString('$_namespace$key');
    } catch (_) {
      return null;
    }
  }

  Future<void> write({required String key, required String? value}) async {
    try {
      final prefs = await _prefs;
      if (value == null) {
        await prefs.remove('$_namespace$key');
      } else {
        await prefs.setString('$_namespace$key', value);
      }
    } catch (_) {
      // Mirrors the real plugin's contract used by MV2: a storage failure must
      // not brick the app.
    }
  }

  Future<void> delete({required String key}) async {
    try {
      await (await _prefs).remove('$_namespace$key');
    } catch (_) {}
  }

  Future<void> deleteAll() async {
    try {
      final prefs = await _prefs;
      for (final key in prefs.getKeys().toList(growable: false)) {
        if (key.startsWith(_namespace)) await prefs.remove(key);
      }
    } catch (_) {}
  }

  Future<bool> containsKey({required String key}) async =>
      (await read(key: key)) != null;

  Future<Map<String, String>> readAll() async {
    final prefs = await _prefs;
    return <String, String>{
      for (final key in prefs.getKeys())
        if (key.startsWith(_namespace)) key.substring(_namespace.length): '${prefs.get(key)}',
    };
  }
}
