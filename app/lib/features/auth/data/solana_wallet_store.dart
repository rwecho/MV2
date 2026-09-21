import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 「记住钱包」的 Solana 私钥（opt-in，默认不保存）。
///
/// 私钥是能转走钱包全部资产的凭据，因此只在用户勾选记住时写入，且与
/// 会话 cookie 一样放在 keychain/keystore（`FlutterSecureStorage`），绝不
/// 落 `SharedPreferences`。读取失败按未保存处理，不能阻塞登录。
class SolanaWalletStore {
  SolanaWalletStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _keySecret = 'mv2.auth.solana.secret';
  static const String _keyAddress = 'mv2.auth.solana.address';

  final FlutterSecureStorage _storage;

  /// The remembered wallet, or `null` when none was saved (or the keystore
  /// failed — forgetting a wallet must never break sign-in).
  Future<({String secretKey, String address})?> read() async {
    try {
      final secret = await _storage.read(key: _keySecret);
      if (secret == null || secret.isEmpty) return null;
      final address = await _storage.read(key: _keyAddress) ?? '';
      return (secretKey: secret, address: address);
    } catch (_) {
      return null;
    }
  }

  Future<void> write({required String secretKey, required String address}) async {
    try {
      await _storage.write(key: _keySecret, value: secretKey);
      await _storage.write(key: _keyAddress, value: address);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _keySecret);
      await _storage.delete(key: _keyAddress);
    } catch (_) {}
  }
}

final solanaWalletStoreProvider = Provider<SolanaWalletStore>(
  (ref) => SolanaWalletStore(),
);
