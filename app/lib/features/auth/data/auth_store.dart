import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auth_session.dart';

/// Persists the non-secret part of the session (username / avatar / member id).
///
/// The session cookie is stored separately by `SecureCookieStorage` through the
/// `cookie_jar`, so both live in the keychain/keystore and never in
/// `SharedPreferences`.
class AuthStore {
  AuthStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'mv2.auth.';

  final FlutterSecureStorage _storage;

  Future<AuthSession?> read() async {
    try {
      final raw = <String, String?>{
        'username': await _storage.read(
          key:
              '$_prefix'
              'username',
        ),
        'memberId': await _storage.read(
          key:
              '$_prefix'
              'memberId',
        ),
        'avatar': await _storage.read(
          key:
              '$_prefix'
              'avatar',
        ),
        'signedInAt': await _storage.read(
          key:
              '$_prefix'
              'signedInAt',
        ),
      };
      return AuthSession.fromStorage(raw);
    } catch (_) {
      // A broken keystore must not brick the app.
      return null;
    }
  }

  Future<void> write(AuthSession session) async {
    final values = session.toStorage();
    for (final entry in values.entries) {
      await _write('$_prefix${entry.key}', entry.value);
    }
  }

  Future<void> clear() async {
    for (final key in <String>[
      'username',
      'memberId',
      'avatar',
      'signedInAt',
    ]) {
      try {
        await _storage.delete(key: '$_prefix$key');
      } catch (_) {}
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }
}
