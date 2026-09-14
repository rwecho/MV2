import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/features/reader/data/reader_article.dart';

void main() {
  group('normalizeJsResult', () {
    test('unwraps the quoted string WKWebView returns', () {
      const payload = '{"ok":true,"title":"Hi"}';
      final quoted = jsonEncode(payload);
      expect(normalizeJsResult(quoted), payload);
    });

    test('passes a bare payload through', () {
      const payload = '{"ok":true}';
      expect(normalizeJsResult(payload), payload);
    });

    test('handles null and non-string results', () {
      expect(normalizeJsResult(null), isNull);
      expect(normalizeJsResult(42), '42');
    });
  });

  group('decodeReaderResult', () {
    const sourceUrl = 'https://example.com/post';
    const payload = <String, Object?>{
      'ok': true,
      'title': 'A title',
      'byline': 'Jane Doe',
      'siteName': 'Example',
      'excerpt': 'Summary',
      'content': '<div><p>Body</p></div>',
      'textLength': 1234,
    };

    test('maps a full payload onto ReaderArticle', () {
      final article = decodeReaderResult(
        jsonEncode(payload),
        sourceUrl: sourceUrl,
      );
      expect(article, isNotNull);
      expect(article!.title, 'A title');
      expect(article.byline, 'Jane Doe');
      expect(article.siteName, 'Example');
      expect(article.excerpt, 'Summary');
      expect(article.contentHtml, '<div><p>Body</p></div>');
      expect(article.textLength, 1234);
      expect(article.sourceUrl, sourceUrl);
    });

    test('returns null for {ok:false}', () {
      expect(
        decodeReaderResult('{"ok":false}', sourceUrl: sourceUrl),
        isNull,
      );
      expect(
        decodeReaderResult(
          '{"ok":false,"error":"boom"}',
          sourceUrl: sourceUrl,
        ),
        isNull,
      );
    });

    test('returns null for malformed or non-object JSON', () {
      expect(decodeReaderResult('not json', sourceUrl: sourceUrl), isNull);
      expect(decodeReaderResult('', sourceUrl: sourceUrl), isNull);
      expect(decodeReaderResult(null, sourceUrl: sourceUrl), isNull);
      expect(decodeReaderResult('[1,2,3]', sourceUrl: sourceUrl), isNull);
      expect(decodeReaderResult('"a string"', sourceUrl: sourceUrl), isNull);
    });

    test('returns null when ok is true but content is unusable', () {
      expect(
        decodeReaderResult('{"ok":true}', sourceUrl: sourceUrl),
        isNull,
      );
      expect(
        decodeReaderResult('{"ok":true,"content":""}', sourceUrl: sourceUrl),
        isNull,
      );
      expect(
        decodeReaderResult('{"ok":true,"content":"   "}', sourceUrl: sourceUrl),
        isNull,
      );
      expect(
        decodeReaderResult('{"ok":true,"content":null}', sourceUrl: sourceUrl),
        isNull,
      );
    });

    test('tolerates missing optional fields and blank strings', () {
      final article = decodeReaderResult(
        jsonEncode(<String, Object?>{
          'ok': true,
          'content': '<p>x</p>',
          'title': '  ',
          'byline': null,
          'textLength': '900',
        }),
        sourceUrl: sourceUrl,
      );
      expect(article, isNotNull);
      expect(article!.title, isNull);
      expect(article.byline, isNull);
      expect(article.siteName, isNull);
      // Numeric strings are coerced; a missing length degrades to 0.
      expect(article.textLength, 900);
    });

    test('defaults a missing textLength to zero', () {
      final article = decodeReaderResult(
        '{"ok":true,"content":"<p>x</p>"}',
        sourceUrl: sourceUrl,
      );
      expect(article!.textLength, 0);
      expect(article.readingMinutes, 1);
    });
  });

  group('readerMinutesFor', () {
    test('is ceil(textLength / 400) with a one-minute floor', () {
      expect(readerMinutesFor(0), 1);
      expect(readerMinutesFor(-10), 1);
      expect(readerMinutesFor(1), 1);
      expect(readerMinutesFor(400), 1);
      expect(readerMinutesFor(401), 2);
      expect(readerMinutesFor(800), 2);
      expect(readerMinutesFor(801), 3);
      expect(readerMinutesFor(4000), 10);
      expect(readerMinutesFor(4001), 11);
    });
  });
}
