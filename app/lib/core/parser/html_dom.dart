import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Small, defensive wrapper around `package:html`.
///
/// V2EX pages are hand-written HTML with `&nbsp;` separators and Chinese
/// literals; these helpers centralise the cleaning so parsers stay readable.
Document parseHtmlDocument(String source) => html_parser.parse(source);

extension Mv2ElementQueries on Element {
  /// Inner text of the first match, cleaned; `null` when absent or blank.
  String? textOf(String selector) => cleanText(querySelector(selector)?.text);

  /// Attribute of the first match; `null` when absent or blank.
  String? attrOf(String selector, String name) {
    final value = querySelector(selector)?.attributes[name];
    return (value == null || value.trim().isEmpty) ? null : value.trim();
  }

  /// `innerHtml` of the first match; `null` when absent.
  String? htmlOf(String selector) => querySelector(selector)?.innerHtml.trim();

  List<Element> allOf(String selector) => querySelectorAll(selector);

  /// Whitespace-collapsed inner text of this element.
  String? get cleanedText => cleanText(text);
}

/// Normalises `&nbsp;`, collapses runs of whitespace and trims.
String? cleanText(String? raw) {
  if (raw == null) return null;
  final normalised = raw
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[ \t\r\n]+'), ' ')
      .trim();
  return normalised.isEmpty ? null : normalised;
}

/// V2EX renders write-action rejections as `div.problem ul li` — the same shape
/// for sign-in, two-step verification and topic publishing.
List<String> parseProblemList(String html) {
  final document = parseHtmlDocument(html);
  return document
      .querySelectorAll('div.problem li')
      .map((element) => cleanText(element.text))
      .whereType<String>()
      .toList(growable: false);
}

int? parseIntOrNull(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'\d+').firstMatch(raw);
  if (match == null) return null;
  return int.tryParse(match.group(0)!);
}

/// V2EX mixes protocol-relative, root-relative and absolute URLs.
String? absoluteV2exUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final value = url.trim();
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('/')) return 'https://www.v2ex.com$value';
  return value;
}

/// `2.3k` → 2300, `54` → 54. V2EX renders some counters compactly.
int? parseCompactCount(String? raw) {
  final text = cleanText(raw);
  if (text == null) return null;
  final match = RegExp(r'(\d+(?:\.\d+)?)\s*([kmKM]?)').firstMatch(text);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  return switch (match.group(2)?.toLowerCase()) {
    'k' => (value * 1000).round(),
    'm' => (value * 1000000).round(),
    _ => value.round(),
  };
}

/// Extracts the numeric id from a V2EX URL (`/t/123456#reply1` → `123456`).
int? parseIdFromUrl(String? url) {
  if (url == null) return null;
  final match = RegExp(r'/(\d+)(?:[#?].*)?$').firstMatch(url.trim());
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// `r_123456` → `123456` (reply cell id).
String? parseReplyId(String? cellId) {
  if (cellId == null) return null;
  final match = RegExp(r'r_(\d+)').firstMatch(cellId);
  return match?.group(1);
}

/// Splits a `topic_info` line into its `•`-separated segments.
///
/// V2EX uses the literal `&nbsp;•&nbsp;` between node, author, time and count.
List<String> splitInfoSegments(String? raw) {
  final text = cleanText(raw);
  if (text == null) return const <String>[];
  return text
      .split('•')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
}
