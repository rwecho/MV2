import 'package:flutter/foundation.dart' show debugPrint;

import '../../shared/models/account_info.dart';
import '../../shared/models/daily_mission.dart';
import '../../shared/models/login_form.dart';
import '../../shared/models/models.dart';
import '../../shared/models/notification_page.dart';
import '../../shared/models/publish_form.dart';
import '../../shared/models/topic_detail.dart';
import '../../shared/models/write_result.dart';
import '../errors/failures.dart';
import '../network/mv2_http_client.dart';
import '../network/v2ex_endpoints.dart';
import '../storage/http_cache.dart';
import '../telemetry/mv2_telemetry.dart';
import '../parser/account_parser.dart';
import '../parser/feed_parser.dart';
import '../parser/html_dom.dart';
import '../parser/login_parser.dart';
import '../parser/member_parser.dart';
import '../parser/node_parser.dart';
import '../parser/notification_parser.dart';
import '../parser/publish_parser.dart';
import '../parser/search_parser.dart';
import '../parser/thanks_parser.dart';
import '../parser/topic_parser.dart';
import '../parser/xna_parser.dart';
import 'home_tab.dart';

/// The V2EX data source contract consumed by the feature repositories.
///
/// The only implementation is [RemoteV2exApi], which talks to the live site.
/// When a request fails the error propagates to the UI layer, which renders
/// the standard failure state — there is no offline sample fallback.
abstract interface class V2exApi {
  /// Topic list for one of the home tabs (`/?tab={slug}`). Only the topic
  /// tabs — `HomeTab.vxna` is an aggregator and is served by [xna].
  Future<List<V2Topic>> feed(HomeTab tab);

  /// VXNA aggregator (`/xna`): external articles, not on-site topics.
  Future<List<V2XnaEntry>> xna();
  Future<V2TopicDetail> topicDetail(int topicId, {int page});
  Future<V2NodePage> nodePage(String nodeName, {int page});
  Future<List<V2Node>> nodes();

  /// Signed-in notification feed (`/notifications`). Anonymous sessions get
  /// [NotificationPage.signedOut] instead of an error.
  Future<NotificationPage> notifications({int page});

  /// Public member profile (`/member/{username}`); `null` when the member does
  /// not exist.
  Future<V2Profile?> member(String username);

  /// sov2ex topic search. [sort] is the raw sov2ex value (`sumup` / `created`);
  /// [from] is the result offset.
  Future<List<V2Topic>> searchTopics(String query, {int from, String sort});

  /// User search. Resolves the site's user-result section when present and
  /// falls back to an exact-username member lookup.
  Future<List<V2User>> searchUsers(String query);

  /// The signed-in account scraped from the home page sidebar, or `null` when
  /// the session is gone (the signed-out shell has no `#Rightbar` avatar).
  Future<V2AccountInfo?> currentUser();

  /// `/mission/daily` — daily bonus state.
  Future<V2DailyMission> dailyMission();

  /// Claims the daily bonus; returns the refreshed state.
  Future<V2DailyMission> checkIn();

  /// Scrapes `/signin` for the randomised field names, `once` and captcha URL.
  /// `null` when the page is not a usable login form.
  Future<V2LoginForm?> loginForm();

  /// Raw captcha bytes. [captchaPath] comes from [V2LoginForm.captchaPath].
  Future<List<int>> captchaImage(String captchaPath, {String? once});

  /// Native form login. Success is V2EX's `302`; a `200` carries the errors.
  Future<V2LoginResult> login({
    required V2LoginForm form,
    required String username,
    required String password,
    required String captcha,
  });

  /// Second step for accounts with two-step verification enabled.
  Future<V2LoginResult> twoStep({
    required V2LoginForm form,
    required String code,
  });

  /// Scrapes `/new` (or `/new/{node}`) for the topic form's `once`.
  ///
  /// Throws [AuthFailure] when the session is gone — V2EX answers an anonymous
  /// request for `/new` with `302 → /signin`.
  Future<V2TopicForm> topicForm({String? node});

  /// Publishes a topic (`POST /new`).
  ///
  /// Success is the `302 → /t/{id}` redirect; a `200` carries a `Problem`
  /// block whose messages land in [V2PublishResult.errors].
  Future<V2PublishResult> publishTopic({
    required V2TopicForm form,
    required String nodeName,
    required String title,
    required String content,
  });

  // -------------------------------------------------------- write actions
  //
  // `docs/12` §4. Every method requires the session `once` token scraped from
  // the page the action belongs to; a missing/expired token is the caller's
  // problem (the UI must not send a request without one). Success is V2EX's
  // `302`; a `200` carries the rejection messages in `V2WriteResult.errors`.
  //
  // 401/403 are mapped to `AuthFailure` and anti-flood pages to
  // `RateLimitFailure` by the HTTP client; those are thrown, not returned.

  /// Replies to a topic (`POST /t/{id}`, form `{content, once}`).
  Future<V2WriteResult> replyToTopic(int topicId, String content, String once);

  /// Thanks the topic itself (`POST /thank/topic/{id}?once=`).
  Future<V2WriteResult> thankTopic(int topicId, String once);

  /// Thanks a single reply (`POST /thank/reply/{replyId}?once=`).
  Future<V2WriteResult> thankReply(String replyId, String once);

  /// Favourites a topic (`GET /favorite/topic/{id}?once=`).
  Future<V2WriteResult> favoriteTopic(int topicId, String once);

  /// Removes a topic from favourites (`GET /unfavorite/topic/{id}?once=`).
  Future<V2WriteResult> unfavoriteTopic(int topicId, String once);

  /// Ignores a topic (`GET /ignore/topic/{id}?once=`).
  Future<V2WriteResult> ignoreTopic(int topicId, String once);

  /// Reverses [ignoreTopic] (`GET /unignore/topic/{id}?once=`).
  Future<V2WriteResult> unignoreTopic(int topicId, String once);

  /// Ignores a single reply (`POST /ignore/reply/{replyId}?once=`).
  Future<V2WriteResult> ignoreReply(String replyId, String once);

  /// Appends `附言` to a topic (`POST /t/{id}/append`, form `{content, once}`).
  Future<V2WriteResult> appendTopic(int topicId, String content, String once);

  /// Ignores a node (`POST /settings/ignore/node/{nodeId}?once=`).
  Future<V2WriteResult> ignoreNode(String nodeId, String once);
}

/// Talks to `www.v2ex.com` through the paced, cookie-aware HTTP client.
class RemoteV2exApi implements V2exApi {
  RemoteV2exApi(this._client, {this.cache, this.onCacheFallback});

  final Mv2HttpClient _client;

  /// Anonymous-page disk cache; `null` disables the offline fallback.
  final HttpCache? cache;

  /// Notified whenever a read is served from (or returns to) the network, so
  /// the UI can tell the user it is looking at cached content instead of
  /// silently pretending everything is fine.
  final void Function(bool fromCache)? onCacheFallback;

  /// True when the most recent read was served from disk because the network
  /// failed — drives the `MV2` cache indicator (`docs/12` §6, defect B6 fix).
  bool lastResponseFromCache = false;

  /// Process-lifetime cache of `/api/nodes/all.json` (numeric id → node).
  /// sov2ex search hits only carry the numeric id, so this is how a result
  /// resolves its real node slug/title. `null` until the first search.
  Map<int, V2Node>? _nodeDirectory;

  /// Single-flight load of [_nodeDirectory]. Holding the future — not just the
  /// result — means concurrent searches share one download.
  Future<Map<int, V2Node>>? _nodeDirectoryLoad;

  /// GET with an offline fallback to the disk cache.
  ///
  /// Only anonymous pages are cached (`HttpCache.isCacheable`), so a signed-in
  /// page can never be served to a different session.
  ///
  /// [rejectRedirect] turns a 3xx into a [Failure] instead of handing the
  /// (usually empty) redirect body to a parser. Topic detail needs it: V2EX
  /// answers `302 → /restricted → /signin?next=/restricted` for a topic the
  /// signed-out session may not read, and parsing that empty body produced a
  /// misleading "页面结构可能已变更" parse error instead of a sign-in prompt.
  Future<String> _getHtml(
    String path, {
    String? referer,
    bool rejectRedirect = false,
  }) async {
    try {
      final result = await _client.get(path, referer: referer);
      if (rejectRedirect && result.isRedirect) {
        throw _redirectFailure(result);
      }
      lastResponseFromCache = false;
      onCacheFallback?.call(false);
      await cache?.write(path, result.body);
      return result.body;
    } on NetworkFailure {
      final cached = await cache?.read(path);
      if (cached == null) rethrow;
      lastResponseFromCache = true;
      onCacheFallback?.call(true);
      return cached;
    }
  }

  /// Classifies a 3xx that stopped an anonymous HTML read. V2EX sends a
  /// signed-out session to `/restricted` (which itself 302s to
  /// `/signin?next=/restricted`); any other redirect means the page is gone.
  static Failure _redirectFailure(HttpResult result) {
    final location = result.location ?? '';
    if (location.contains('/signin') || location.contains('/restricted')) {
      return const AuthFailure(message: '该主题需要登录后查看。');
    }
    return const NotFoundFailure();
  }

  @override
  Future<List<V2Topic>> feed(HomeTab tab) async {
    // Every topic tab is the same page with a different `?tab=` value; the
    // page renders the tab's rows inside the usual `div.cell.item` list, so a
    // single parser covers them all (verified live on `hot`/`all`/`r2`).
    final html = await _getHtml(
      tab.path,
      referer: '${V2exEndpoints.baseUrl}${V2exEndpoints.home}',
    );
    try {
      return FeedParser.parseTopicList(html);
    } catch (error, stack) {
      // A device/region-specific page variant (anti-bot, carrier injection)
      // surfaces here first — report it with the payload size so the console
      // shows what was actually served.
      Mv2Telemetry.recordNonFatal(
        error,
        stack,
        reason: 'feed ${tab.path} (${html.length}B)',
      );
      rethrow;
    }
  }

  @override
  Future<List<V2XnaEntry>> xna() async {
    return XnaParser.parse(
      await _getHtml(
        V2exEndpoints.xna,
        referer: '${V2exEndpoints.baseUrl}${V2exEndpoints.home}',
      ),
    );
  }

  @override
  Future<V2TopicDetail> topicDetail(int topicId, {int page = 1}) async {
    final path = V2exEndpoints.topic(topicId, page: page);
    final body = await _getHtml(
      path,
      referer: '${V2exEndpoints.baseUrl}${V2exEndpoints.home}',
      // A restricted/login-only topic answers `302 → /restricted`; surface that
      // as an auth failure so the page can offer 去登录 (see `_redirectFailure`).
      rejectRedirect: true,
    );
    return TopicParser.parse(body, topicId: topicId);
  }

  @override
  Future<V2NodePage> nodePage(String nodeName, {int page = 1}) async {
    final body = await _getHtml(
      V2exEndpoints.nodeTopics(nodeName, page: page),
      referer: '${V2exEndpoints.baseUrl}/go/$nodeName',
    );
    return NodeParser.parseNodePage(body, nodeName: nodeName);
  }

  @override
  Future<List<V2Node>> nodes() async {
    final json = await _client.getJson(V2exEndpoints.apiNodesList);
    final nodes = NodeParser.parseNodesJson(json);
    // `/api/nodes/s2.json` returns all ~1400 nodes in slug order, while the
    // design needs 热门节点 — so rank by topic count here (the old
    // `/api/nodes/list.json` used to do this with `sort_by=topics&reverse=1`,
    // but that endpoint now answers 400).
    nodes.sort((a, b) => (b.topicCount ?? 0).compareTo(a.topicCount ?? 0));
    return nodes;
  }

  @override
  Future<NotificationPage> notifications({int page = 1}) async {
    final path = V2exEndpoints.notifications(page: page);
    try {
      final result = await _client.get(
        path,
        referer: '${V2exEndpoints.baseUrl}${V2exEndpoints.home}',
      );
      lastResponseFromCache = false;
      // Anonymous sessions are redirected to /signin and the client never
      // follows redirects, so a 3xx here means "not signed in".
      if (result.isRedirect) return const NotificationPage.signedOut();
      // Confirmed: HttpCache.isCacheable('/notifications') is false, so this
      // write is a no-op and the offline fallback below can never serve
      // another session's notifications.
      await cache?.write(path, result.body);
      return NotificationParser.parse(result.body);
    } on NetworkFailure {
      final cached = await cache?.read(path);
      if (cached == null) rethrow;
      lastResponseFromCache = true;
      return NotificationParser.parse(cached);
    }
  }

  @override
  Future<V2Profile?> member(String username) async {
    try {
      final body = await _getHtml(
        V2exEndpoints.member(username),
        referer: '${V2exEndpoints.baseUrl}${V2exEndpoints.home}',
      );
      return MemberParser.parseMemberPage(body);
    } on NotFoundFailure {
      return null;
    }
  }

  /// sov2ex caps a page at 1000; MV2 has no pager in phase 2B, so one page of
  /// 20 is enough to fill the screen.
  static const int _searchPageSize = 20;

  /// The numeric-id node directory, downloaded at most once per process.
  Future<Map<int, V2Node>> _ensureNodeDirectory() {
    final cached = _nodeDirectory;
    if (cached != null) return Future<Map<int, V2Node>>.value(cached);
    return _nodeDirectoryLoad ??= _loadNodeDirectory();
  }

  Future<Map<int, V2Node>> _loadNodeDirectory() async {
    try {
      final json = await _client.getJson(V2exEndpoints.apiNodesAll);
      final directory = NodeParser.parseAllNodesJson(json);
      _nodeDirectory = directory;
      return directory;
    } on Failure catch (error) {
      // Non-fatal: search keeps working and hits render the `节点 {id}`
      // fallback rather than the whole search failing on a directory hiccup.
      debugPrint(
        'MV2: /api/nodes/all.json unavailable ($error); '
        'search node names fall back to numeric ids.',
      );
      const empty = <int, V2Node>{};
      _nodeDirectory = empty;
      return empty;
    }
  }

  @override
  Future<List<V2Topic>> searchTopics(
    String query, {
    int from = 0,
    String sort = 'sumup',
  }) async {
    // Warm the node directory before parsing so `_source.node` (a number) can
    // be resolved to its real slug/title.
    final directory = await _ensureNodeDirectory();
    final json = await _client.getJsonOn(
      V2exEndpoints.searchBaseUrl,
      '/api/search',
      query: <String, dynamic>{
        'q': query,
        'from': from,
        'size': _searchPageSize,
        'sort': sort,
      },
    );
    return SearchParser.parseSov2ex(json, directory: directory);
  }

  @override
  Future<List<V2User>> searchUsers(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const <V2User>[];

    // Documented path: the site search page. Live `/search?q=` now answers
    // `302 → /go/search` (the `search` node) and carries no user section, so
    // this normally yields nothing and the exact-match fallback below runs.
    final result = await _client.get(
      '/search',
      query: <String, dynamic>{'q': term},
    );
    final users = SearchParser.parseSiteSearch(result.body);
    if (users.isNotEmpty) return users;

    // Live fallback: the public member API resolves an exact username.
    try {
      final json = await _client.getJson(V2exEndpoints.apiMemberInfo(term));
      final user = _member(json);
      return user == null ? const <V2User>[] : <V2User>[user];
    } on NotFoundFailure {
      return const <V2User>[];
    }
  }

  /// `/api/members/show.json` → [V2User]; `null` when the payload is unusable.
  static V2User? _member(Object? json) {
    if (json is! Map) return null;
    final username = cleanText(json['username']?.toString());
    if (username == null) return null;
    final avatar =
        (json['avatar_large'] ?? json['avatar_normal'] ?? json['avatar_mini'])
            ?.toString();
    return V2User(
      username: username,
      avatarUrl: absoluteV2exUrl(avatar),
      id: switch (json['id']) {
        final num value => value.toInt(),
        _ => null,
      },
      tagline: cleanText(json['tagline']?.toString()),
    );
  }

  @override
  Future<V2AccountInfo?> currentUser() async {
    // `/` is public, so it answers 200 either way; a signed-out session simply
    // has no `#Rightbar` avatar and the parser returns null.
    final result = await _client.get(
      V2exEndpoints.home,
      referer: '${V2exEndpoints.baseUrl}/',
    );
    return AccountParser.parseCurrentUser(result.body);
  }

  @override
  Future<V2DailyMission> dailyMission() async {
    final result = await _client.get(
      V2exEndpoints.dailyMission,
      referer: '${V2exEndpoints.baseUrl}/',
    );
    // `/mission/daily` is login-only: V2EX answers 302 to `/signin` with an
    // empty body, which must surface as an auth failure rather than as
    // "nothing to claim".
    if (result.isRedirect || result.body.trim().isEmpty) {
      throw const AuthFailure();
    }
    return DailyMissionParser.parse(result.body);
  }

  @override
  Future<V2DailyMission> checkIn() async {
    final mission = await dailyMission();
    final path = mission.redeemPath;
    if (path == null) return mission;
    await _client.get(
      path,
      referer: '${V2exEndpoints.baseUrl}${V2exEndpoints.dailyMission}',
    );
    return dailyMission();
  }

  @override
  Future<V2LoginForm?> loginForm() async {
    final result = await _client.get(
      V2exEndpoints.signInWithNext,
      referer: '${V2exEndpoints.baseUrl}/',
    );
    if (result.isRedirect) {
      // `/signin/cooldown` is an IP throttle (verified live after repeated
      // failed attempts) — not "already signed in". Reporting it as a missing
      // form made the page blame a markup change.
      if (result.location?.contains(V2exEndpoints.signInCooldown) ?? false) {
        throw const RateLimitFailure(
          message: '登录尝试过于频繁，V2EX 暂时限制了登录，请稍后再试。',
        );
      }
      // An already-authenticated session is redirected away from `/signin`.
      return null;
    }
    return LoginFormParser.parse(result.body);
  }

  @override
  Future<List<int>> captchaImage(String captchaPath, {String? once}) {
    final separator = captchaPath.contains('?') ? '&' : '?';
    final buffer = StringBuffer(captchaPath)
      ..write(separator)
      ..write('now=${DateTime.now().millisecondsSinceEpoch}');
    if (once != null && once.isNotEmpty) buffer.write('&once=$once');
    return _client.getBytes(
      buffer.toString(),
      referer: '${V2exEndpoints.baseUrl}${V2exEndpoints.signIn}',
    );
  }

  @override
  Future<V2LoginResult> login({
    required V2LoginForm form,
    required String username,
    required String password,
    required String captcha,
  }) async {
    final result = await _client.postForm(
      V2exEndpoints.signIn,
      referer: '${V2exEndpoints.baseUrl}${V2exEndpoints.signIn}',
      data: <String, String>{
        form.usernameFieldName: username,
        form.passwordFieldName: password,
        form.captchaFieldName: captcha,
        'once': form.once,
        'next': form.next,
      },
    );

    // V2EX signals success with 302 + a changed Location (`docs/12` §4).
    if (result.isRedirect) {
      return V2LoginResult(
        success: !LoginFormParser.isTwoFactorRedirect(result.location),
        twoFactor: LoginFormParser.isTwoFactorRedirect(result.location),
      );
    }
    return V2LoginResult(
      success: false,
      errors: LoginFormParser.parseErrors(result.body),
    );
  }

  @override
  Future<V2LoginResult> twoStep({
    required V2LoginForm form,
    required String code,
  }) async {
    final result = await _client.postForm(
      V2exEndpoints.twoFactor,
      referer: '${V2exEndpoints.baseUrl}${V2exEndpoints.signIn}',
      data: <String, String>{'code': code, 'once': form.once},
    );
    if (result.isRedirect) return const V2LoginResult(success: true);
    return V2LoginResult(
      success: false,
      errors: LoginFormParser.parseErrors(result.body),
    );
  }

  @override
  Future<V2TopicForm> topicForm({String? node}) async {
    final path = V2exEndpoints.createTopicForm(node: node);
    final result = await _client.get(
      path,
      // `/new` is login-only, so an anonymous session is redirected away.
      referer: '${V2exEndpoints.baseUrl}${V2exEndpoints.createTopicForm()}',
    );
    if (result.isRedirect) throw const AuthFailure();

    final form = PublishParser.parseForm(result.body, pathNode: node);
    if (form == null) {
      throw const ParseFailure('new topic page: once input not found');
    }
    return form;
  }

  @override
  Future<V2PublishResult> publishTopic({
    required V2TopicForm form,
    required String nodeName,
    required String title,
    required String content,
  }) async {
    final result = await _client.postForm(
      V2exEndpoints.createTopicSubmit,
      // The write is validated against the form page it came from.
      referer:
          '${V2exEndpoints.baseUrl}${V2exEndpoints.createTopicForm(node: nodeName)}',
      data: <String, String>{
        'title': title,
        'syntax': 'default',
        'content': content,
        'node_name': nodeName,
        'once': form.once,
      },
    );

    if (result.isRedirect) {
      return V2PublishResult(
        success: true,
        topicId: PublishParser.parseTopicId(result.location),
      );
    }
    final errors = PublishParser.parseErrors(result.body);
    return V2PublishResult(
      success: false,
      errors: errors,
      // Silence + a re-rendered form = the session rejected our `once`.
      invalidToken: errors.isEmpty && PublishParser.isStaleToken(result.body),
    );
  }

  // ---------------------------------------------------------- write actions

  /// Maps a write response to [V2WriteResult]: `302` is success, anything else
  /// that reached this point is a `200` rejection whose `div.problem ul li`
  /// block carries the messages (`LoginFormParser.parseErrors`).
  static V2WriteResult _writeOutcome(HttpResult result) {
    if (result.isRedirect) {
      // A signed-out session answers a write with `302 → /signin`; reporting
      // that as success would leave the optimistic UI lying.
      if ((result.location ?? '').contains('/signin')) {
        throw const AuthFailure();
      }
      return const V2WriteResult(success: true);
    }
    return V2WriteResult(
      success: false,
      errors: LoginFormParser.parseErrors(result.body),
    );
  }

  /// `/thank/*` answers `200` JSON instead of `302` (`ThanksParser`).
  static V2WriteResult _thanksOutcome(HttpResult result) {
    if (result.isRedirect) {
      if ((result.location ?? '').contains('/signin')) {
        throw const AuthFailure();
      }
      return const V2WriteResult(success: true);
    }
    return ThanksParser.parse(result.body);
  }

  /// Referer used by reply-scoped actions, where the topic id is not part of
  /// the method signature and therefore cannot be reconstructed.
  String get _siteReferer => '${V2exEndpoints.baseUrl}/';

  @override
  Future<V2WriteResult> replyToTopic(
    int topicId,
    String content,
    String once,
  ) async {
    final result = await _client.postForm(
      V2exEndpoints.reply(topicId),
      referer: V2exEndpoints.topicReferer(topicId),
      data: <String, String>{'content': content, 'once': once},
    );
    return _writeOutcome(result);
  }

  @override
  Future<V2WriteResult> thankTopic(int topicId, String once) async {
    final result = await _client.post(
      V2exEndpoints.withOnce(V2exEndpoints.thankTopic(topicId), once),
      referer: V2exEndpoints.topicReferer(topicId),
    );
    return _thanksOutcome(result);
  }

  @override
  Future<V2WriteResult> thankReply(String replyId, String once) async {
    final result = await _client.post(
      V2exEndpoints.withOnce(V2exEndpoints.thankReply(replyId), once),
      referer: _siteReferer,
    );
    return _thanksOutcome(result);
  }

  @override
  Future<V2WriteResult> favoriteTopic(int topicId, String once) async {
    final result = await _client.get(
      V2exEndpoints.withOnce(V2exEndpoints.favoriteTopic(topicId), once),
      referer: V2exEndpoints.topicReferer(topicId),
    );
    return _writeOutcome(result);
  }

  @override
  Future<V2WriteResult> unfavoriteTopic(int topicId, String once) async {
    final result = await _client.get(
      V2exEndpoints.withOnce(V2exEndpoints.unfavoriteTopic(topicId), once),
      referer: V2exEndpoints.topicReferer(topicId),
    );
    return _writeOutcome(result);
  }

  @override
  Future<V2WriteResult> ignoreTopic(int topicId, String once) async {
    final result = await _client.get(
      V2exEndpoints.withOnce(V2exEndpoints.ignoreTopic(topicId), once),
      referer: V2exEndpoints.topicReferer(topicId),
    );
    return _writeOutcome(result);
  }

  @override
  Future<V2WriteResult> unignoreTopic(int topicId, String once) async {
    final result = await _client.get(
      V2exEndpoints.withOnce(V2exEndpoints.unignoreTopic(topicId), once),
      referer: V2exEndpoints.topicReferer(topicId),
    );
    return _writeOutcome(result);
  }

  @override
  Future<V2WriteResult> ignoreReply(String replyId, String once) async {
    final result = await _client.post(
      V2exEndpoints.withOnce(V2exEndpoints.ignoreReply(replyId), once),
      referer: _siteReferer,
    );
    return _writeOutcome(result);
  }

  @override
  Future<V2WriteResult> appendTopic(
    int topicId,
    String content,
    String once,
  ) async {
    final result = await _client.postForm(
      V2exEndpoints.append(topicId),
      referer: V2exEndpoints.topicReferer(topicId),
      data: <String, String>{'content': content, 'once': once},
    );
    return _writeOutcome(result);
  }

  @override
  Future<V2WriteResult> ignoreNode(String nodeId, String once) async {
    final result = await _client.post(
      V2exEndpoints.withOnce(V2exEndpoints.ignoreNode(nodeId), once),
      referer: '${V2exEndpoints.baseUrl}/settings/ignore/node',
    );
    return _writeOutcome(result);
  }
}
