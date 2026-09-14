import 'package:html/dom.dart';

import '../../shared/models/models.dart';
import '../../shared/models/node_visuals.dart';
import 'html_dom.dart';

/// Parses V2EX topic-list pages into [V2Topic].
///
/// Verified against live markup (2026-09-11). The real item shape is:
///
/// ```html
/// <div class="cell item">            <!-- home / recent / my / tag -->
///   <td><a href="/member/x"><img class="avatar"></a></td>
///   <td>
///     <span class="item_title"><a href="/t/123#reply4">标题</a></span>
///     <span class="topic_info">
///       <div class="votes"></div>
///       <a class="node" href="/go/programmer">程序员</a> &nbsp;•&nbsp;
///       <strong><a href="/member/x">作者</a></strong> &nbsp;•&nbsp;
///       <span title="ISO">3 小时前</span> &nbsp;•&nbsp;
///       最后回复来自 <strong><a href="/member/y">y</a></strong>
///     </span>
///   </td>
///   <td width="70" align="right"><a class="count_livid">42</a></td>
/// </div>
/// ```
///
/// Node pages (`/go/{node}`) use `#TopicsNode > div.cell` with no `.item`
/// class and no `a.node` (the node is implied by the page).
abstract final class FeedParser {
  /// Home tabs, `/recent`, `/my/*`, `/tag/{tag}`.
  static List<V2Topic> parseTopicList(String html) {
    final document = parseHtmlDocument(html);
    return document
        .querySelectorAll('div.cell.item')
        .map((element) => _parseItem(element))
        .whereType<V2Topic>()
        .toList(growable: false);
  }

  /// `/go/{node}` — `#TopicsNode > div.cell`, with the node supplied by the
  /// caller because the item markup omits the node link.
  static List<V2Topic> parseNodeTopicList(
    String html, {
    required String nodeName,
    String? nodeTitle,
  }) {
    final document = parseHtmlDocument(html);
    final container = document.querySelector('#TopicsNode') ?? document;
    return container
        .querySelectorAll('div.cell')
        .map(
          (element) => _parseItem(
            element,
            nodeFallback: nodeName,
            nodeTitleFallback: nodeTitle,
          ),
        )
        .whereType<V2Topic>()
        .toList(growable: false);
  }

  static V2Topic? _parseItem(
    Element item, {
    String? nodeFallback,
    String? nodeTitleFallback,
  }) {
    final titleAnchor = item.querySelector('span.item_title a');
    final title = cleanText(titleAnchor?.text);
    if (title == null || titleAnchor == null) return null;

    final href = titleAnchor.attributes['href'];
    final id = parseIdFromUrl(href);
    if (id == null) return null;

    final info = item.querySelector('span.topic_info');
    final nodeAnchor = info?.querySelector('a.node');
    final nodeName = cleanText(nodeAnchor?.text) ?? nodeTitleFallback ?? '未知节点';
    final nodeKey =
        _nodeKey(nodeAnchor?.attributes['href']) ?? nodeFallback ?? 'unknown';

    // The first `<strong>` is the topic author; a later one (preceded by
    // `最后回复来自`) is the last replier.
    final strongs = info?.querySelectorAll('strong a') ?? const <Element>[];
    final authorName = strongs.isNotEmpty
        ? cleanText(strongs.first.text)
        : null;

    // The relative time lives in the first `span[title]`, which also carries an
    // absolute timestamp in `title`.
    final timeElement = info?.querySelector('span[title]');
    final timeLabel = cleanText(timeElement?.text) ?? '';

    return V2Topic(
      id: id,
      node: NodeVisuals.node(key: nodeKey, name: nodeName),
      title: title,
      author: V2User(
        username: authorName ?? '匿名',
        avatarUrl: absoluteV2exUrl(item.attrOf('td a img', 'src')),
      ),
      createdAtLabel: timeLabel,
      // The count anchor sits in a sibling `<td>`, not inside `topic_info`.
      replyCount: _replyCount(item),
      url: absoluteV2exUrl(href),
    );
  }

  /// First `a` whose class starts with `count_` (`count_livid`, `count_gray`…).
  static int _replyCount(Element item) {
    for (final anchor in item.querySelectorAll('a')) {
      final className = anchor.attributes['class'] ?? '';
      if (className.contains('count_')) {
        return parseIntOrNull(anchor.text) ?? 0;
      }
    }
    return 0;
  }

  /// `/go/programmer` → `programmer`.
  static String? _nodeKey(String? href) {
    if (href == null || href.isEmpty) return null;
    final match = RegExp(r'/go/([^/?#]+)').firstMatch(href);
    return match?.group(1);
  }
}
