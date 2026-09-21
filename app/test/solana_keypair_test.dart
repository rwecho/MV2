import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/solana/base58.dart';
import 'package:mv2/core/solana/solana_keypair.dart';

/// RFC 8032 §7.1 TEST 1 (ed25519) — proves the signing is standard ed25519,
/// not something Phantom-compatible-looking.
const String _rfcSeedHex =
    '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
const String _rfcPubHex =
    'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
const String _rfcEmptyMessageSigHex =
    'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
    '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b';

List<int> _hexToBytes(String hex) {
  final result = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    result.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return result;
}

void main() {
  group('SolanaKeypair.parse', () {
    test('accepts a 64-byte base58 secret (Phantom export format)', () async {
      final seed = _hexToBytes(_rfcSeedHex);
      final publicKey = _hexToBytes(_rfcPubHex);
      final keypair = await SolanaKeypair.parse(
        Base58.encode(<int>[...seed, ...publicKey]),
      );
      expect(keypair.address, Base58.encode(publicKey));
    });

    test('accepts a 32-byte base58 seed', () async {
      final keypair = await SolanaKeypair.parse(
        Base58.encode(_hexToBytes(_rfcSeedHex)),
      );
      expect(keypair.address, Base58.encode(_hexToBytes(_rfcPubHex)));
    });

    test('rejects a 64-byte secret whose trailing key mismatches', () async {
      final seed = _hexToBytes(_rfcSeedHex);
      final wrongKey = _hexToBytes(_rfcPubHex)..[0] ^= 0xff;
      expect(
        () => SolanaKeypair.parse(Base58.encode(<int>[...seed, ...wrongKey])),
        throwsFormatException,
      );
    });

    test('rejects non-base58 and wrong-length input', () async {
      expect(() => SolanaKeypair.parse('not base58!'), throwsFormatException);
      expect(() => SolanaKeypair.parse(''), throwsFormatException);
      expect(() => SolanaKeypair.parse('111'), throwsFormatException);
    });
  });

  group('SolanaKeypair.signHex', () {
    test('produces the RFC 8032 signature for the empty message', () async {
      final keypair = await SolanaKeypair.parse(
        Base58.encode(_hexToBytes(_rfcSeedHex)),
      );
      // The message the V2EX web client signs is UTF-8; an empty message
      // matches the RFC vector byte for byte.
      expect(await keypair.signHex(''), _rfcEmptyMessageSigHex);
    });

    test('signs the V2EX login message deterministically', () async {
      final keypair = await SolanaKeypair.parse(
        Base58.encode(_hexToBytes(_rfcSeedHex)),
      );
      final message = 'Sign in to V2EX: 1758417000';
      final first = await keypair.signHex(message);
      final second = await keypair.signHex(utf8.decode(utf8.encode(message)));
      expect(first, second);
      expect(first.length, 128); // 64 bytes, lowercase hex
    });
  });

  group('SolanaKeypair.maskedAddress', () {
    test('shortens long addresses', () async {
      final keypair = await SolanaKeypair.parse(
        Base58.encode(_hexToBytes(_rfcSeedHex)),
      );
      final address = keypair.address;
      expect(
        keypair.maskedAddress,
        '${address.substring(0, 6)}…${address.substring(address.length - 4)}',
      );
    });
  });
}
