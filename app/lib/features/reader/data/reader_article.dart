import 'dart:convert';

/// A successfully extracted article — the native output of reader mode.
///
/// Produced by injecting Mozilla Readability into a [WebView] and decoding the
/// JSON it returns (`reader_extractor.dart`). Everything here is plain data so
/// the mapping can be unit-tested without a device.
class ReaderArticle {
  const ReaderArticle({
    required this.title,
    required this.byline,
    required this.siteName,
    required this.excerpt,
    required this.contentHtml,
    required this.textLength,
    required this.sourceUrl,
  });

  /// Article headline as Readability resolved it (may be null/empty).
  final String? title;

  /// Author line, e.g. `Jane Doe`.
  final String? byline;

  /// Publication name, e.g. `The Verge`.
  final String? siteName;

  /// Short summary; currently unused by the UI but part of the payload.
  final String? excerpt;

  /// Sanitised article HTML, with relative `src`/`href` already absolutised by
  /// Readability.
  final String contentHtml;

  /// Plain-text length of the article body, used for the reading-time estimate.
  final int textLength;

  /// The URL the article was extracted from.
  final String sourceUrl;

  /// Estimated reading time in minutes (`ceil(textLength / 400)`, min 1).
  int get readingMinutes => readerMinutesFor(textLength);
}

/// Reading-time estimate for a plain-text [textLength].
///
/// 400 characters per minute is the convention inherited from the legacy MV2
/// client; the minimum is one minute so a two-line article never reads `约 0 分钟`.
int readerMinutesFor(int textLength) {
  if (textLength <= 0) return 1;
  return (textLength / 400).ceil();
}

/// Normalises the value returned by
/// `WebViewController.runJavaScriptReturningResult`.
///
/// The platform channels marshal a JS **string** in either of two shapes: the
/// bare payload, or a JSON-encoded string (i.e. wrapped in quotes with escaped
/// inner quotes). Unwrap the latter so callers always see the real payload.
String? normalizeJsResult(Object? result) {
  if (result == null) return null;
  var value = result is String ? result : result.toString();
  final trimmed = value.trim();
  if (trimmed.length >= 2 &&
      trimmed.startsWith('"') &&
      trimmed.endsWith('"')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is String) value = decoded;
    } catch (_) {
      // Not JSON after all — fall through with the raw value.
    }
  }
  return value;
}

/// Decodes the JSON string produced by the injected Readability snippet.
///
/// Returns `null` for every failure shape: a null/empty payload, malformed
/// JSON, a non-object payload, `{"ok":false}` (Readability bailed out), or an
/// `ok:true` result whose `content` is missing/blank. A non-null result always
/// has non-empty HTML and a [ReaderArticle.sourceUrl] of [sourceUrl].
ReaderArticle? decodeReaderResult(String? raw, {required String sourceUrl}) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  if (decoded['ok'] != true) return null;

  final content = decoded['content'];
  if (content is! String || content.trim().isEmpty) return null;

  return ReaderArticle(
    title: _string(decoded['title']),
    byline: _string(decoded['byline']),
    siteName: _string(decoded['siteName']),
    excerpt: _string(decoded['excerpt']),
    contentHtml: content,
    textLength: _int(decoded['textLength']) ?? 0,
    sourceUrl: sourceUrl,
  );
}

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _int(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
