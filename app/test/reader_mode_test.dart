import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/features/reader/application/reader_mode.dart';
import 'package:mv2/features/settings/application/settings_controller.dart';

void main() {
  group('initialReaderMode', () {
    test('an explicit ?mode= wins over the setting', () {
      expect(
        initialReaderMode(
          queryMode: 'original',
          setting: Mv2LinkOpenMode.reader,
        ),
        ReaderMode.original,
      );
      expect(
        initialReaderMode(
          queryMode: 'reader',
          setting: Mv2LinkOpenMode.original,
        ),
        ReaderMode.reader,
      );
    });

    test('falls back to the persisted 外链打开方式 setting', () {
      expect(
        initialReaderMode(setting: Mv2LinkOpenMode.reader),
        ReaderMode.reader,
      );
      expect(
        initialReaderMode(setting: Mv2LinkOpenMode.original),
        ReaderMode.original,
      );
    });

    test('an unknown query value falls back to the setting', () {
      expect(
        initialReaderMode(
          queryMode: 'nonsense',
          setting: Mv2LinkOpenMode.original,
        ),
        ReaderMode.original,
      );
      // `browser` never reaches the reader page, but degrades to reader mode.
      expect(
        initialReaderMode(setting: Mv2LinkOpenMode.browser),
        ReaderMode.reader,
      );
    });
  });

  group('readerRoute', () {
    test('encodes the url and omits mode when unspecified', () {
      final route = readerRoute('https://example.com/a?b=1&c=2#frag');
      final uri = Uri.parse(route);
      expect(uri.path, '/reader');
      expect(uri.queryParameters['url'], 'https://example.com/a?b=1&c=2#frag');
      expect(uri.queryParameters.containsKey('mode'), isFalse);
    });

    test('pins the starting mode when given', () {
      final uri = Uri.parse(
        readerRoute('https://example.com/x', mode: ReaderMode.original),
      );
      expect(uri.queryParameters['mode'], 'original');

      final reader = Uri.parse(
        readerRoute('https://example.com/x', mode: ReaderMode.reader),
      );
      expect(reader.queryParameters['mode'], 'reader');
    });
  });
}
