import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [Storage] implementation for `cookie_jar`'s [PersistCookieJar] backed by the
/// platform keychain/keystore.
///
/// The V2EX session cookie is account-equivalent credential material, so it must
/// live in secure storage rather than `SharedPreferences` (`docs/12` §7).
class SecureCookieStorage implements Storage {
  SecureCookieStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'mv2.cookie.';

  final FlutterSecureStorage _storage;

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {
    // Nothing to warm up: values are read lazily per key.
  }

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: '$_prefix$key');
    } catch (_) {
      // A broken keystore must not brick the app; treat as "no cookie".
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: '$_prefix$key', value: value);
    } catch (_) {
      // Ignore: the in-memory jar still has the cookie for this session.
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: '$_prefix$key');
    } catch (_) {}
  }

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      await delete(key);
    }
  }
}

/// Non-persistent storage used by tests and by the fixture-mode client.
class InMemoryCookieStorage implements Storage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {}

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      _values.remove(key);
    }
  }
}
