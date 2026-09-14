import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';

import '../../../core/errors/failures.dart';
import '../../../core/network/mv2_http_client.dart';
import '../../../core/parser/feed_parser.dart';
import '../../../core/parser/html_dom.dart';
import '../../../core/parser/pagination_parser.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/node_visuals.dart';
import '../../../shared/models/topic_detail.dart';

/// One page of a 我的 list: rows plus V2EX's own pager window.
///
/// Mirrors [V2NodePage] (`topics` + [V2Pagination]) so the page can keep
/// loading `p + 1` until `pagination.maximum`.
@immutable
class MyTopicPage {
  const MyTopicPage({required this.topics, required this.pagination});

  final List<V2Topic> topics;
  final V2Pagination pagination;

  static const MyTopicPage empty = MyTopicPage(
    topics: <V2Topic>[],
    pagination: V2Pagination(),
  );
}

/// Endpoint paths for the 我的 pages.
///
/// **Live-verified 2026** (see `my_api_test.dart` and the phase report):
///
/// | page | path | signed-in anon probe |
/// |------|------|----------------------|
/// | 我的主题 | `/member/{username}/topics` | `200` |
/// | 我的回复 | `/member/{username}/replies` | `200` |
/// | 收藏 (favourite topics) | `/my/topics` | `302 → /signin` |
/// | 我的节点 (favourite nodes) | `/my/nodes` | `302 → /signin` |
///
/// The task brief guessed `/my/replies` and `/my/favorites/topics`; both answer
/// **404** on the live site, so the member-scoped pages are used for a member's
/// own topics/replies and `/my/topics` is the favourites list. `/my/following`
/// (关注) also exists but has no UI in this phase.
abstract final class MyEndpoints {
  static String memberTopics(String username, {int page = 1}) => page <= 1
      ? '/member/$username/topics'
      : '/member/$username/topics?p=$page';

  static String memberReplies(String username, {int page = 1}) => page <= 1
      ? '/member/$username/replies'
      : '/member/$username/replies?p=$page';

  static String favoriteTopics({int page = 1}) =>
      page <= 1 ? '/my/topics' : '/my/topics?p=$page';

  static const String favoriteNodes = '/my/nodes';
}

/// Feature-local data source for the 我的 pages.
///
/// It deliberately does **not** touch [V2exApi] (another agent owns that file):
/// it takes the shared [Mv2HttpClient] and reuses [FeedParser] /
/// [NodeParser]-style parsing from `core/parser`.
///
/// Every request carries `Referer: https://www.v2ex.com/my/`, as V2EX requires
/// for the signed-in surfaces.
class MyApi {
  MyApi(this._client, {this.username});

  final Mv2HttpClient _client;

  /// Signed-in member name. 我的主题 / 我的回复 are member-scoped pages, so they
  /// are unavailable without it; the providers never call them while signed out.
  final String? username;

  static const String _referer = 'https://www.v2ex.com/my/';

  /// 我的主题 — the signed-in member's own topics.
  Future<MyTopicPage> myTopics({int page = 1}) {
    final name = username;
    if (name == null || name.isEmpty) {
      return Future<MyTopicPage>.value(MyTopicPage.empty);
    }
    return _topicPage(MyEndpoints.memberTopics(name, page: page));
  }

  /// 我的回复 — topics the signed-in member replied to, newest reply first.
  ///
  /// The member replies page is **not** the `div.cell.item` feed shape: each
  /// entry is a `dock_area` + `inner` pair, parsed feature-locally into a
  /// [V2Topic] (the reply text becomes the excerpt).
  Future<MyTopicPage> myReplies({int page = 1}) async {
    final name = username;
    if (name == null || name.isEmpty) return MyTopicPage.empty;
    final html = await _getHtml(MyEndpoints.memberReplies(name, page: page));
    return MyTopicPage(
      topics: _parseMemberReplies(html),
      pagination: _paginationOf(html),
    );
  }

  /// 收藏 — the signed-in member's favourite topics (`/my/topics`).
  Future<MyTopicPage> favoriteTopics({int page = 1}) {
    return _topicPage(MyEndpoints.favoriteTopics(page: page));
  }

  /// 我的节点 — the signed-in member's favourite nodes (`/my/nodes`).
  Future<List<V2Node>> favoriteNodes() async {
    final html = await _getHtml(MyEndpoints.favoriteNodes);
    return _parseFavoriteNodes(html);
  }

  // ------------------------------------------------------------- internals

  Future<MyTopicPage> _topicPage(String path) async {
    final html = await _getHtml(path);
    return MyTopicPage(
      // `/my/topics` and `/member/{u}/topics` are the standard feed item shape.
      topics: FeedParser.parseTopicList(html),
      pagination: _paginationOf(html),
    );
  }

  Future<String> _getHtml(String path) async {
    final result = await _client.get(path, referer: _referer);
    // The client never follows redirects; a 3xx on a signed-in-only page means
    // the session lapsed (the providers guard this too).
    if (result.isRedirect) throw const AuthFailure();
    return result.body;
  }

  V2Pagination _paginationOf(String html) {
    final document = parseHtmlDocument(html);
    return parsePagination(document.body ?? document.documentElement!);
  }

  /// Parses `/member/{username}/replies`.
  ///
  /// Live shape:
  /// ```html
  /// <div class="dock_area"><table><tr><td>
  ///   <div class="fr"><span class="fade">11 小时 20 分钟前</span></div>
  ///   <span class="gray">回复了 <a href="/member/author">author</a> 创建的主题
  ///     <span class="chevron">›</span> <a href="/go/create">分享创造</a>
  ///     <span class="chevron">›</span>
  ///     <a href="/t/1240867#reply77">标题</a></span>
  /// </td></tr></table></div>
  /// <div class="inner"><div class="reply_content">@… 内容</div></div>
  /// ```
  static List<V2Topic> _parseMemberReplies(String html) {
    final document = parseHtmlDocument(html);
    final topics = <V2Topic>[];

    for (final dock in document.querySelectorAll('div.dock_area')) {
      final topicAnchor = dock
          .querySelectorAll('a')
          .where((a) => (a.attributes['href'] ?? '').contains('/t/'))
          .firstOrNull;
      if (topicAnchor == null) continue;
      final href = topicAnchor.attributes['href'];
      final id = parseIdFromUrl(href);
      final title = cleanText(topicAnchor.text);
      if (id == null || title == null) continue;

      final nodeAnchor = dock
          .querySelectorAll('a')
          .where((a) => (a.attributes['href'] ?? '').startsWith('/go/'))
          .firstOrNull;
      final nodeKey = _nodeKey(nodeAnchor?.attributes['href']) ?? 'unknown';
      final nodeName = cleanText(nodeAnchor?.text) ?? nodeKey;

      // "回复了 <author> 创建的主题" — the member link that is NOT the node/topic
      // link is the topic author.
      final authorAnchor = dock
          .querySelectorAll('a[href^="/member/"]')
          .firstOrNull;
      final authorName = cleanText(authorAnchor?.text) ?? '匿名';

      final timeLabel = cleanText(dock.querySelector('span.fade')?.text) ?? '';
      final excerpt = cleanText(
        dock.nextElementSibling?.querySelector('.reply_content')?.text,
      );

      topics.add(
        V2Topic(
          id: id,
          node: NodeVisuals.node(key: nodeKey, name: nodeName),
          title: title,
          author: V2User(username: authorName),
          createdAtLabel: timeLabel,
          replyCount: 0,
          excerpt: excerpt,
          url: absoluteV2exUrl(href),
        ),
      );
    }
    return topics;
  }

  /// Parses `/my/nodes`.
  ///
  /// Live shape (captured 2026 from the signed-in app):
  /// ```html
  /// <div class="cell" id="my-nodes">
  ///   <a class="fav-node" href="/go/programmer" id="n_300">
  ///     <img …>
  ///     <span class="fav-node-name">程序员</span>
  ///     <span class="f12 fade"><i class="fa fa-comments"></i> 73295</span>
  ///   </a>
  ///   …
  /// </div>
  /// ```
  static List<V2Node> _parseFavoriteNodes(String html) {
    final document = parseHtmlDocument(html);
    final nodes = <V2Node>[];
    final seen = <String>{};

    for (final anchor in document.querySelectorAll('a[href^="/go/"]')) {
      final key = _nodeKey(anchor.attributes['href']);
      if (key == null || !seen.add(key)) continue;

      final text = cleanText(anchor.text) ?? '';
      final name =
          cleanText(anchor.querySelector('.fav-node-name')?.text) ??
          _nameFromText(text);
      if (name == null) {
        seen.remove(key);
        continue;
      }

      nodes.add(
        NodeVisuals.node(
          key: key,
          name: name,
          topicCount: _favoriteCount(anchor, text),
        ),
      );
    }
    return nodes;
  }

  /// `程序员 73295` → `程序员`.
  static String? _nameFromText(String text) {
    final match = RegExp(r'^(.+?)\s+[\d,\.]+[kKmM]?$').firstMatch(text);
    return cleanText(match?.group(1) ?? text);
  }

  /// The count sits in `span.fade` (`<i class="fa fa-comments"></i> 73295`);
  /// fall back to a trailing number in the anchor text.
  static int? _favoriteCount(Element anchor, String text) {
    final fade = cleanText(anchor.querySelector('span.fade')?.text);
    if (fade != null) {
      final value = parseCompactCount(fade);
      if (value != null) return value;
    }
    final match = RegExp(r'([\d,\.]+[kKmM]?)\s*$').firstMatch(text);
    return match == null ? null : parseCompactCount(match.group(1));
  }

  static String? _nodeKey(String? href) {
    if (href == null || href.isEmpty) return null;
    final match = RegExp(r'/go/([^/?#]+)').firstMatch(href);
    return match?.group(1);
  }
}
