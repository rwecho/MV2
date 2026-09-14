import '../../shared/models/models.dart';
import '../../shared/models/node_visuals.dart';
import '../errors/failures.dart';
import 'html_dom.dart';

/// Parses the two search payloads MV2 consumes.
///
/// ## sov2ex topic search — verified against the live API (2026-09-11)
///
/// `GET https://www.sov2ex.com/api/search?q=codex&from=0&size=5&sort=created`
/// returns an Elasticsearch-shaped object. Only `sumup` (权重/相关度) and
/// `created` (发帖时间) are accepted for `sort` — anything else answers
/// `400 {"message":"invalid sort"}`, so there is **no reply-count ordering**.
///
/// ```json
/// {
///   "took": 255,
///   "total": 5799,
///   "timed_out": false,
///   "hits": [
///     {
///       "_score": null,
///       "_index": "topic_v1",
///       "_type": "topic",
///       "_id": "1241319",
///       "sort": [1789106895000],
///       "highlight": { "content": ["…兼容 Claude Code 、<em>Codex</em>…"] },
///       "_source": {
///         "node": 864,
///         "replies": 0,
///         "created": "2026-09-11T06:08:15",
///         "member": "alynn",
///         "id": 1241319,
///         "title": "[CUBENCE] 周年庆活动来啦！…",
///         "content": "这里是 Cubence …"
///       }
///     }
///   ]
/// }
/// ```
///
/// `node` is the **numeric V2EX node id**, not the slug, and sov2ex never
/// returns the node name. When the caller supplies a `directory` built from
/// `/api/nodes/all.json` (numeric `id` → `{name, title}`), the hit is resolved
/// to its real slug/title; otherwise [V2Node.key] carries the id and
/// [V2Node.name] is rendered as `节点 {id}`. `highlight` is only present when
/// the match sits in that field; it is preferred for the excerpt because it
/// wraps the query term in `<em>`.
///
/// ## site user search — verified against the live site (2026-09-11)
///
/// `GET https://www.v2ex.com/search?q=codex` now answers `302 → /go/search`,
/// i.e. the `search` **node** page, which renders topic authors but no user
/// result block. [parseSiteSearch] is therefore anchored on a dedicated user
/// container and returns an empty list when it is absent (the live case),
/// rather than mis-reading the topic authors as search hits.
abstract final class SearchParser {
  /// Maximum excerpt length, matching [NodeParser]'s topic-content trimming.
  static const int _excerptLength = 120;

  /// sov2ex `/api/search` → topics. Throws [ParseFailure] when the envelope is
  /// unrecognisable; individual malformed hits are skipped.
  ///
  /// [directory] optionally maps a numeric V2EX node id to the real
  /// [V2Node] (`/api/nodes/all.json`); when it lacks the hit's node, the
  /// `节点 {id}` fallback is kept.
  static List<V2Topic> parseSov2ex(
    Object? json, {
    Map<int, V2Node>? directory,
  }) {
    if (json is! Map) {
      throw const ParseFailure('sov2ex search: expected a JSON object');
    }
    final hits = json['hits'];
    if (hits is! List) {
      throw const ParseFailure('sov2ex search: "hits" is not a list');
    }

    final topics = <V2Topic>[];
    for (final hit in hits) {
      if (hit is! Map) continue;
      final topic = _parseHit(hit, directory);
      if (topic != null) topics.add(topic);
    }
    return topics;
  }

  /// `/search?q=` HTML → users, or an empty list when the page carries no
  /// user-result section (the current live behaviour).
  static List<V2User> parseSiteSearch(String html) {
    final document = parseHtmlDocument(html);
    final section = document.querySelector(
      'div#search-user, div.search_user, div.user_results, ul.user-list',
    );
    if (section == null) return const <V2User>[];

    final users = <V2User>[];
    final seen = <String>{};
    for (final anchor in section.querySelectorAll('a[href*="/member/"]')) {
      final username =
          cleanText(anchor.text) ??
          _usernameFromHref(anchor.attributes['href']);
      if (username == null || !seen.add(username)) continue;
      users.add(
        V2User(
          username: username,
          avatarUrl: absoluteV2exUrl(
            anchor.querySelector('img')?.attributes['src'],
          ),
        ),
      );
    }
    return users;
  }

  // ------------------------------------------------------------------- hits

  static V2Topic? _parseHit(
    Map<dynamic, dynamic> hit,
    Map<int, V2Node>? directory,
  ) {
    final source = hit['_source'];
    final map = source is Map ? source : hit;

    final id = switch (map['id']) {
      final num value => value.toInt(),
      _ => parseIdFromUrl(hit['_id']?.toString()),
    };
    final title = cleanText(map['title']?.toString());
    if (id == null || title == null) return null;

    // sov2ex only exposes the numeric node id; the slug and display name are
    // not part of the response. Resolve it against the all-nodes directory
    // when one was supplied, otherwise fall back to `节点 {id}`.
    final nodeId = switch (map['node']) {
      final num value => value.toInt(),
      _ => null,
    };
    final nodeValue =
        nodeId?.toString() ??
        switch (map['node']) {
          final String value when value.trim().isNotEmpty => value.trim(),
          _ => null,
        };
    final resolved = nodeId == null ? null : directory?[nodeId];

    return V2Topic(
      id: id,
      node:
          resolved ??
          NodeVisuals.node(
            key: nodeValue ?? 'unknown',
            name: nodeValue == null ? '未知节点' : '节点 $nodeValue',
          ),
      title: title,
      author: V2User(username: cleanText(map['member']?.toString()) ?? '匿名'),
      createdAtLabel: _relativeLabel(map['created']?.toString()),
      replyCount: switch (map['replies']) {
        final num value => value.toInt(),
        _ => 0,
      },
      excerpt: _excerpt(hit, map),
      url: 'https://www.v2ex.com/t/$id',
    );
  }

  /// Prefers the search-hit highlight (query context) over the raw body.
  static String? _excerpt(
    Map<dynamic, dynamic> hit,
    Map<dynamic, dynamic> source,
  ) {
    final highlight = hit['highlight'];
    if (highlight is Map) {
      final content = highlight['content'];
      if (content is List && content.isNotEmpty) {
        final text = _plainText(content.first?.toString());
        if (text != null) return text;
      }
    }
    return _plainText(source['content']?.toString());
  }

  /// Strips V2EX/sov2ex inline markup (`<em>`), collapses whitespace and caps
  /// the length so a card never renders a wall of text.
  static String? _plainText(String? raw) {
    final text = cleanText(raw?.replaceAll(RegExp(r'<[^>]*>'), ' '));
    if (text == null) return null;
    return text.length > _excerptLength
        ? '${text.substring(0, _excerptLength)}...'
        : text;
  }

  /// `2026-09-11T06:08:15` → `3 小时前` / `2026-09-11` on parse failure.
  static String _relativeLabel(String? raw) {
    final text = cleanText(raw);
    if (text == null) return '';
    final created = DateTime.tryParse(text);
    if (created == null) return text;

    final elapsed = DateTime.now().difference(created);
    if (elapsed.isNegative || elapsed.inMinutes < 1) return '刚刚';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
    if (elapsed.inDays < 1) return '${elapsed.inHours} 小时前';
    if (elapsed.inDays < 30) return '${elapsed.inDays} 天前';
    return text.split('T').first;
  }

  static String? _usernameFromHref(String? href) {
    if (href == null) return null;
    final match = RegExp(r'/member/([^/?#]+)').firstMatch(href);
    return match?.group(1);
  }
}
