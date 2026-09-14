import 'package:html/dom.dart';

import '../../shared/models/models.dart';
import '../../shared/models/node_visuals.dart';
import '../../shared/models/topic_detail.dart';
import '../errors/failures.dart';
import 'html_dom.dart';
import 'pagination_parser.dart';

/// Parses `/t/{id}?p={page}` into [V2TopicDetail].
///
/// Everything is anchored under `div#Wrapper` (the C# contract); if that
/// container is missing the site structure changed and we fail loudly with
/// [ParseFailure] instead of rendering an empty topic.
abstract final class TopicParser {
  static V2TopicDetail parse(String html, {required int topicId}) {
    final document = parseHtmlDocument(html);
    final wrapper = document.querySelector('div#Wrapper');
    if (wrapper == null) {
      throw const ParseFailure('topic page: div#Wrapper not found');
    }

    final header = wrapper.querySelector('div.header');
    final title = cleanText(header?.querySelector('h1')?.text) ?? '';
    final authorAnchor = header?.querySelector('small a');
    final authorName = cleanText(authorAnchor?.text);

    final nodeAnchor = header?.querySelector('a[href*="/go/"]');
    final nodeName = cleanText(nodeAnchor?.text) ?? '未知节点';

    // The relative time is a `span[title]` (title carries the absolute
    // timestamp); the trailing `· 6600 次点击` stays in the `small` text.
    final createdText = cleanText(
      header?.querySelector('small span[title]')?.text,
    );
    final statsLabel = _trailingStat(header?.querySelector('small')?.text);

    final favoriteAnchor = wrapper.querySelector('a[href*="favorite/topic"]');
    final favoriteLabel = cleanText(favoriteAnchor?.text);
    final thankedLabel = cleanText(
      wrapper.querySelector('div#topic_thank span')?.text,
    );
    final ignoreAnchor = wrapper.querySelector('a[onclick*="/ignore/topic"]');
    final ignoreLabel = cleanText(ignoreAnchor?.text);

    final contentHtml = wrapper.htmlOf('div.cell div.topic_content');
    final replies = _parseReplies(wrapper, authorName);

    final topic = V2Topic(
      id: topicId,
      node: NodeVisuals.node(
        key: _nodeKey(nodeAnchor?.attributes['href']),
        name: nodeName,
      ),
      title: title,
      author: V2User(
        username: authorName ?? replies.firstOrNull?.author.username ?? '匿名',
        avatarUrl: absoluteV2exUrl(header?.attrOf('div.fr img', 'src')),
      ),
      createdAtLabel: createdText ?? '',
      replyCount: replies.length,
      body: contentHtml == null ? null : <String>[contentHtml],
      url: 'https://www.v2ex.com/t/$topicId',
    );

    return V2TopicDetail(
      topic: topic,
      contentHtml: contentHtml,
      supplements: _parseSupplements(wrapper),
      tags: wrapper
          .querySelectorAll('a.tag')
          .map((element) => cleanText(element.text))
          .whereType<String>()
          .toList(growable: false),
      statsLabel: statsLabel ?? _statsLabel(favoriteAnchor),
      replyStatsLabel: _replyStatsLabel(wrapper),
      favorited: favoriteLabel == '取消收藏',
      thanked: thankedLabel == '感谢已发送',
      ignored: ignoreLabel == '取消忽略',
      once: wrapper.attrOf('input#once', 'value'),
      pagination: parsePagination(wrapper),
      replies: replies,
    );
  }

  // --------------------------------------------------------------- replies

  static List<V2Reply> _parseReplies(Element wrapper, String? topicAuthor) {
    final replies = <V2Reply>[];
    for (final cell in wrapper.querySelectorAll('div.cell')) {
      final id = cell.attributes['id'];
      if (id == null || !id.startsWith('r_')) continue;

      final strong = cell.querySelector('td strong');
      final authorAnchor = strong?.querySelector('a');
      final username = cleanText(authorAnchor?.text);
      final spansAfterStrong = _spansAfter(strong);

      final badges = cell
          .querySelectorAll('div.badges .badge')
          .map((element) => cleanText(element.text))
          .whereType<String>()
          .toList(growable: false);

      final contentElement = cell.querySelector('td div.reply_content');
      final contentHtml = contentElement?.innerHtml.trim();
      final thankedElement = cell.querySelector('div.thanked');

      replies.add(
        V2Reply(
          id: parseReplyId(id),
          floor: parseIntOrNull(cell.querySelector('span.no')?.text) ?? 0,
          author: V2User(
            username: username ?? '匿名',
            avatarUrl: absoluteV2exUrl(cell.attrOf('img.avatar', 'src')),
          ),
          content: cleanText(contentElement?.text) ?? '',
          contentHtml: (contentHtml?.isEmpty ?? true) ? null : contentHtml,
          createdAtLabel: cleanText(spansAfterStrong.firstOrNull?.text) ?? '',
          likes: parseIntOrNull(spansAfterStrong.elementAtOrNull(1)?.text) ?? 0,
          thanked: cleanText(thankedElement?.text) != null,
          // V2EX marks the author's own replies with `badge op`; the name
          // comparison is the fallback when the badge is absent.
          isOwner:
              badges.any((badge) => badge.toUpperCase() == 'OP') ||
              (username != null &&
                  topicAuthor != null &&
                  username == topicAuthor),
          badges: badges,
        ),
      );
    }
    return replies;
  }

  /// `<span>` elements that follow the author `strong` inside the same cell —
  /// `[0]` is the relative time, `[1]` the thanks count (C# contract §3).
  static List<Element> _spansAfter(Element? strong) {
    if (strong == null) return const <Element>[];
    final parent = strong.parent;
    if (parent == null) return const <Element>[];
    final spans = <Element>[];
    var seenStrong = false;
    for (final node in parent.nodes) {
      if (node == strong) {
        seenStrong = true;
        continue;
      }
      if (seenStrong && node is Element && node.localName == 'span') {
        spans.add(node);
      }
    }
    return spans;
  }

  // ------------------------------------------------------------ supplements

  static List<V2Supplement> _parseSupplements(Element wrapper) {
    return wrapper
        .querySelectorAll('div.subtle')
        .map(
          (element) => V2Supplement(
            createdAtLabel: element.textOf('span.fade'),
            contentHtml: element.htmlOf('div.topic_content'),
          ),
        )
        .where((item) => item.contentHtml != null)
        .toList(growable: false);
  }

  // ----------------------------------------------------------------- labels

  /// `ensonfun · 2 小时前 · 6600 次点击` → `6600 次点击`.
  static String? _trailingStat(String? raw) {
    final text = cleanText(raw);
    if (text == null) return null;
    final parts = text.split('·');
    if (parts.length < 2) return null;
    return cleanText(parts.last);
  }

  /// The `span` immediately preceding the favourite anchor, e.g. `4688 次点击`.
  static String? _statsLabel(Element? favoriteAnchor) {
    if (favoriteAnchor == null) return null;
    final parent = favoriteAnchor.parent;
    if (parent == null) return null;
    Element? lastSpan;
    for (final node in parent.nodes) {
      if (node == favoriteAnchor) break;
      if (node is Element && node.localName == 'span') lastSpan = node;
    }
    return cleanText(lastSpan?.text);
  }

  static String? _replyStatsLabel(Element wrapper) {
    for (final span in wrapper.querySelectorAll('div.cell span.gray')) {
      final text = cleanText(span.text);
      if (text == null || !text.contains('回复')) continue;
      // The same `span.gray` also carries `• <absolute timestamp>`, which the
      // reply-count line must not include.
      return cleanText(text.split('•').first);
    }
    return null;
  }

  static String _nodeKey(String? href) {
    if (href == null || href.isEmpty) return 'unknown';
    final match = RegExp(r'/go/([^/?#]+)').firstMatch(href);
    return match?.group(1) ?? 'unknown';
  }
}
