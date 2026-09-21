import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'base58.dart';

/// Solana 钱包密钥对 —— 只为「Sign in with Solana」做本地签名。
///
/// V2EX 的网页端让 Phantom 对 `Sign in to V2EX: <unix 秒>` 做 ed25519 签名，
/// 然后把 hex 签名 + 原文 + base58 公钥 POST 到 `/auth/solana`。手机上没有
/// 浏览器扩展，本类用同一套消息格式在本地完成签名（verified 2026-09-21:
/// 服务端只校验签名与时间戳新鲜度，与签名来源无关）。
///
/// 输入支持两种格式：
/// * Phantom/Solflare 导出的私钥 —— 64 字节的 base58（`seed(32)‖公钥(32)`）；
/// * 32 字节的 base58 种子。
class SolanaKeypair {
  SolanaKeypair._(this._seed, this.publicKey);

  static final Ed25519 _ed25519 = Ed25519();

  /// 32 字节 ed25519 种子。
  final List<int> _seed;

  /// 32 字节公钥；base58 编码后就是 Solana 地址。
  final List<int> publicKey;

  String get address => Base58.encode(publicKey);

  /// Parses a pasted private key; throws [FormatException] when the input is
  /// not valid base58 or not 32/64 bytes long. A 64-byte secret whose trailing
  /// public key does not match the derived one is rejected too — that catches
  /// copy-paste truncation before it turns into a confusing `Invalid
  /// signature` from the server.
  static Future<SolanaKeypair> parse(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('私钥为空');
    }
    final bytes = Base58.decode(trimmed);
    final List<int> seed;
    if (bytes.length == 64) {
      seed = bytes.sublist(0, 32);
    } else if (bytes.length == 32) {
      seed = bytes;
    } else {
      throw const FormatException('私钥长度不是 32/64 字节');
    }
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    final publicKeyBytes = (await keyPair.extractPublicKey()).bytes;
    if (bytes.length == 64) {
      final expectedTail = bytes.sublist(32);
      if (!_constEquals(expectedTail, publicKeyBytes)) {
        throw const FormatException('私钥与自带的公钥不匹配');
      }
    }
    return SolanaKeypair._(seed, List<int>.of(publicKeyBytes));
  }

  /// Signs [message] (UTF-8) and returns the signature as lowercase hex —
  /// the exact encoding the web client sends in `signature`.
  Future<String> signHex(String message) async {
    final keyPair = await _ed25519.newKeyPairFromSeed(_seed);
    final signature = await _ed25519.sign(utf8.encode(message), keyPair: keyPair);
    return _hex(signature.bytes);
  }

  /// 掩码显示用的短地址（`3r6oHL…ZCGE`）。
  String get maskedAddress {
    final a = address;
    return a.length <= 12 ? a : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';
  }
}

String _hex(List<int> bytes) {
  const digits = '0123456789abcdef';
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer
      ..write(digits[(byte >> 4) & 0xf])
      ..write(digits[byte & 0xf]);
  }
  return buffer.toString();
}

/// Constant-time-ish comparison; inputs are 32 bytes so timing is not a real
/// surface here, but avoiding an early return is free.
bool _constEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
