import 'package:html/dom.dart';

import '../../shared/models/models.dart';
import 'feed_parser.dart';
import 'html_dom.dart';

/// Parses `/member/{username}` into a [V2Profile].
///
/// Verified against a real capture of `/member/Livid` (2026-09-11):
///
/// ```html
/// <div class="box">
///   <div class="cell">
///     <table><tr>
///       <td><img src="…" class="avatar" … alt="Livid" data-uid="1" /></td>
///       <td>
///         <h1>Livid</h1>
///         <span class="bigger">Remember the bigger green</span>
///         <span class="gray">V2EX 第 1 号会员，加入于 2010-04-25 …</span>
///       </td>
///     </tr></table>
///   </div>
/// </div>
/// ```
///
/// The anonymous member page does **not** expose topic/reply/favourite counters
/// (confirmed against the live capture), so those selectors are defensive:
/// whenever the header does not carry e.g. `50 个主题` they resolve to `0`
/// instead of failing. The member's recent topics reuse [FeedParser] because
/// the page renders ordinary `div.cell.item` rows.
abstract final class MemberParser {
  static V2Profile? parseMemberPage(String html) {
    final document = parseHtmlDocument(html);
    final wrapper = document.querySelector('div#Wrapper') ?? document.body;
    if (wrapper == null) return null;

    final heading =
        wrapper.querySelector('div.cell h1') ?? wrapper.querySelector('h1');
    final username = cleanText(heading?.text);
    if (username == null || username.isEmpty) return null;

    final headerCell = _closestCell(heading!);
    final avatar =
        headerCell.querySelector('img.avatar') ??
        wrapper.querySelector('img.avatar');
    final headerText = cleanText(headerCell.text) ?? '';

    return V2Profile(
      user: V2User(
        username: username,
        avatarUrl: absoluteV2exUrl(avatar?.attributes['src']),
        id: _memberId(avatar, headerText),
        tagline: cleanText(headerCell.querySelector('span.bigger')?.text),
      ),
      // Defensive: the live anonymous page carries no counters (see class doc).
      topicCount: _counter(headerText, '主题'),
      replyCount: _counter(headerText, '回复'),
      favoriteCount: _counter(headerText, '收藏'),
      joinedAtLabel: _joinedAt(headerText),
      recentTopics: FeedParser.parseTopicList(html),
    );
  }

  /// Nearest `div.cell` ancestor of [element] (the header cell), or [element]
  /// itself when the page shape changed.
  static Element _closestCell(Element element) {
    Element? current = element.parent;
    while (current != null) {
      if (current.localName == 'div' && current.classes.contains('cell')) {
        return current;
      }
      current = current.parent;
    }
    return element;
  }

  /// `data-uid="1"` on the avatar is the canonical id; the header text carries
  /// `V2EX 第 1 号会员` (and some surfaces use `V2EX #1`).
  static int? _memberId(Element? avatar, String headerText) {
    final fromAvatar = parseIntOrNull(avatar?.attributes['data-uid']);
    if (fromAvatar != null) return fromAvatar;

    final numbered = RegExp(r'第\s*(\d+)\s*号会员').firstMatch(headerText);
    if (numbered != null) return int.tryParse(numbered.group(1)!);

    final hashed = RegExp(r'V2EX\s*#\s*(\d+)').firstMatch(headerText);
    if (hashed != null) return int.tryParse(hashed.group(1)!);
    return null;
  }

  /// `50 个主题` / `336 条回复` style counter, when the page renders one.
  static int? _counter(String text, String unit) {
    final match = RegExp('(\\d+)\\s*[个条]?\\s*$unit').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}

/// `V2EX 第 1 号会员，加入于 2010-04-25 21:45:46 +08:00` → `2010-04-25`.
String? _joinedAt(String? raw) {
  final text = cleanText(raw);
  if (text == null) return null;
  final match = RegExp(r'加入于\s*(\d{4}-\d{2}-\d{2})').firstMatch(text);
  return match?.group(1);
}
