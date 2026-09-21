import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/solana/base58.dart';

void main() {
  group('Base58.encode', () {
    test('"hello world" matches the canonical vector', () {
      expect(Base58.encode('hello world'.codeUnits), 'StV1DL6CwTryKyV');
    });

    test('leading zero bytes become leading "1"s', () {
      expect(Base58.encode(<int>[0, 0, 1]), '112');
      expect(Base58.encode(<int>[0, 0, 0]), '111');
    });

    test('empty input stays empty', () {
      expect(Base58.encode(<int>[]), '');
    });

    test('a Solana-sized 32-byte value round-trips through decode', () {
      final bytes = List<int>.generate(32, (i) => (i * 7 + 3) & 0xff);
      expect(Base58.decode(Base58.encode(bytes)), bytes);
    });
  });

  group('Base58.decode', () {
    test('canonical vector decodes back', () {
      expect(Base58.decode('StV1DL6CwTryKyV'), 'hello world'.codeUnits);
    });

    test('rejects characters outside the alphabet', () {
      for (final bad in <String>['0', 'O', 'I', 'l', 'StV 1DL']) {
        expect(
          () => Base58.decode(bad),
          throwsFormatException,
          reason: '"$bad" must not decode',
        );
      }
    });

    test('empty input decodes to empty', () {
      expect(Base58.decode(''), <int>[]);
    });
  });
}
