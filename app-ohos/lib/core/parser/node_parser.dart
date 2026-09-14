import '../../shared/models/models.dart';
import '../../shared/models/node_visuals.dart';
import '../../shared/models/topic_detail.dart';
import '../errors/failures.dart';
import 'feed_parser.dart';
import 'pagination_parser.dart';
import 'html_dom.dart';

/// Parses node-related payloads: the `/go/{node}` page and the public JSON
/// node/hot-topic endpoints (`docs/12` §2.1).
abstract final class NodeParser {
  /// `/go/{node}?p={page}`.
  static V2NodePage parseNodePage(String html, {required String nodeName}) {
    final document = parseHtmlDocument(html);
    final wrapper = document.querySelector('div#Wrapper');
    if (wrapper == null) {
      throw const ParseFailure('node page: div#Wrapper not found');
    }

    // The `/go/{node}` list lives in `#TopicsNode`; the pager uses the shared
    // `a.page_current` / `a.page_normal` markup (the old `div.inner td strong`
    // "1/5" widget no longer exists).
    final title = cleanText(document.querySelector('title')?.text);

    return V2NodePage(
      nodeName: nodeName,
      title: title,
      topics: FeedParser.parseNodeTopicList(
        html,
        nodeName: nodeName,
        nodeTitle: title,
      ),
      pagination: parsePagination(document.body ?? document.documentElement!),
    );
  }

  /// `/api/nodes/s2.json`.
  ///
  /// Live shape: `{ "text": "程序员 / programmer", "id": "programmer",
  /// "topics": 73281, "aliases": ["developer"] }` — `id` is the slug and `text`
  /// is `显示名 / slug`. `/api/nodes/list.json` now answers 400, so `s2.json`
  /// is the source of truth. The `name`/`title` shape is still accepted.
  static List<V2Node> parseNodesJson(Object? json) {
    if (json is! List) {
      throw const ParseFailure('nodes list: expected a JSON array');
    }
    final nodes = <V2Node>[];
    for (final entry in json) {
      if (entry is! Map) continue;
      final id = entry['id']?.toString() ?? entry['name']?.toString();
      final text = entry['text']?.toString();
      final name = id ?? text;
      if (name == null || name.isEmpty) continue;
      final title =
          entry['title']?.toString() ??
          (text != null && text.contains(' / ')
              ? text.split(' / ').first.trim()
              : null) ??
          name;
      final topics = entry['topics'];
      final aliases = entry['aliases'];
      nodes.add(
        NodeVisuals.node(
          key: name,
          name: title,
          topicCount: topics is num ? topics.toInt() : null,
          tags: aliases is List
              ? aliases
                    .map((alias) => alias.toString())
                    .take(3)
                    .toList(growable: false)
              : const <String>[],
        ),
      );
    }
    return nodes;
  }

  /// `/api/nodes/all.json` — the full public node directory.
  ///
  /// Live shape (verified 2026-09-11 through the local proxy: a JSON array of
  /// 1376 nodes, ~800 KB) — each entry carries BOTH the numeric `id` and the
  /// slug:
  ///
  /// ```json
  /// {"id": 300, "name": "programmer", "title": "程序员", "topics": 73280,
  ///  "header": "While code monkeys…", "aliases": [],
  ///  "url": "https://www.v2ex.com/go/programmer", …}
  /// ```
  ///
  /// The numeric id is what sov2ex search hits carry (`_source.node`), so this
  /// map is how a search result resolves back to its real slug/title. Throws
  /// [ParseFailure] on a non-list payload; malformed entries are skipped.
  static Map<int, V2Node> parseAllNodesJson(Object? json) {
    if (json is! List) {
      throw const ParseFailure('all nodes: expected a JSON array');
    }
    final nodes = <int, V2Node>{};
    for (final entry in json) {
      if (entry is! Map) continue;
      final id = switch (entry['id']) {
        final num value => value.toInt(),
        _ => null,
      };
      final name = entry['name']?.toString();
      if (id == null || name == null || name.isEmpty) continue;
      final title = entry['title']?.toString();
      final topics = entry['topics'];
      final aliases = entry['aliases'];
      nodes[id] = NodeVisuals.node(
        key: name,
        name: (title == null || title.isEmpty) ? name : title,
        topicCount: topics is num ? topics.toInt() : null,
        tags: aliases is List
            ? aliases
                  .map((alias) => alias.toString())
                  .take(3)
                  .toList(growable: false)
            : const <String>[],
        nodeId: id,
      );
    }
    return nodes;
  }

  /// `/api/topics/hot.json` — public daily-hot list.
  static List<V2Topic> parseHotTopicsJson(Object? json) {
    if (json is! List) {
      throw const ParseFailure('hot topics: expected a JSON array');
    }
    final topics = <V2Topic>[];
    for (final entry in json) {
      if (entry is! Map) continue;
      final id = switch (entry['id']) {
        final num value => value.toInt(),
        _ => parseIdFromUrl(entry['url']?.toString()),
      };
      final title = cleanText(entry['title']?.toString());
      if (id == null || title == null) continue;

      final nodeJson = entry['node'];
      final memberJson = entry['member'];
      final nodeName = nodeJson is Map ? nodeJson['name']?.toString() : null;
      final nodeTitle = nodeJson is Map ? nodeJson['title']?.toString() : null;
      final username = memberJson is Map
          ? memberJson['username']?.toString()
          : null;
      final avatar = memberJson is Map
          ? (memberJson['avatar_normal'] ?? memberJson['avatar_large'])
                ?.toString()
          : null;

      topics.add(
        V2Topic(
          id: id,
          node: NodeVisuals.node(
            key: nodeName ?? 'unknown',
            name: nodeTitle ?? nodeName ?? '未知节点',
          ),
          title: title,
          author: V2User(
            username: username ?? '匿名',
            avatarUrl: absoluteV2exUrl(avatar),
          ),
          createdAtLabel: '',
          replyCount: switch (entry['replies']) {
            final num value => value.toInt(),
            _ => 0,
          },
          excerpt: _stripHtml(entry['content']?.toString()),
          url: absoluteV2exUrl(entry['url']?.toString()),
        ),
      );
    }
    return topics;
  }

  /// V2EX's JSON API returns HTML fragments in `content`.
  static String? _stripHtml(String? raw) {
    final text = cleanText(raw?.replaceAll(RegExp(r'<[^>]*>'), ' '));
    if (text == null) return null;
    return text.length > 120 ? '${text.substring(0, 120)}...' : text;
  }
}
