/// V2EX endpoints, header values and the Chinese literals the HTML pages use as
/// state signals (`docs/12-v2ex-api-inventory.md`).
///
/// Everything fragile lives here so a site change is a one-file diff.
abstract final class V2exEndpoints {
  static const String host = 'www.v2ex.com';
  static const String baseUrl = 'https://www.v2ex.com';
  static const String searchBaseUrl = 'https://www.sov2ex.com';

  /// Mobile Safari UA used for reads (and login writes). V2EX serves the same
  /// DOM to mobile and desktop UAs (verified 2026-09: home, topic, node,
  /// /signin are byte-identical modulo timestamps), so parsers are UA-agnostic;
  /// the UA matters only because V2EX labels *content-creating* writes with a
  /// `via <platform>` tag parsed from it — see the "write UAs" block below.
  static const String userAgent =
      'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  // -------------------------------------------------------- write UAs
  //
  // V2EX stamps every content-creating post (reply / new topic / append) with
  // a `via <platform>` label parsed from the *posting request's* UA. Reads
  // keep [userAgent] for its stable mobile DOM, but that same iPad UA made
  // every reply on every device read "来自 iPad". The writes therefore present
  // the device we really are (resolved per platform by `V2exWriteUa`):
  // Safari/iOS UAs label as `via iPhone` / `via iPad`, Android Chrome as
  // `via Android`, and desktop Chrome as nothing — matching what the same
  // devices produce on the web. V2EX normalises to the platform name only;
  // concrete models never show up, and the label text is not client-selectable.

  /// iPhone Safari — the honest label for phones (`via iPhone`).
  static const String iPhoneWriteUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 '
      'Safari/604.1';

  /// Android Chrome, in Chrome's own reduced-UA form (`Android 10; K` is the
  /// exact string modern Chrome sends, model never leaves the device) —
  /// V2EX labels it `via Android`.
  static String androidWriteUserAgent() =>
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36';

  /// Desktop Chrome on macOS — produces **no** via label, like posting from
  /// the desktop web. Used for non-handheld platforms (macOS builds).
  static const String desktopWriteUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36';

  // ----------------------------------------------------------------- reads

  /// Feed tabs: `/` with `?tab=`.
  ///
  /// `tab` is one of `tech / creative / play / apple / jobs / deals / city /
  /// qna / hot / all / r2` (`HomeTab`). The site's own `/` renders the `tech`
  /// tab first.
  static String homeTab(String slug) => '/?tab=$slug';
  static const String home = '/';
  static const String recent = '/recent';

  /// VXNA — the external-blog aggregator tab (`HomeTab.vxna`). Shares the
  /// `#Tabs` row with the topic tabs but has its own `div.xna-entry` layout.
  static const String xna = '/xna';
  static String topic(int id, {int page = 1}) =>
      page <= 1 ? '/t/$id' : '/t/$id?p=$page';
  static String nodeTopics(String nodeName, {int page = 1}) =>
      page <= 1 ? '/go/$nodeName' : '/go/$nodeName?p=$page';
  static String tag(String tagName, {int page = 1}) =>
      page <= 1 ? '/tag/$tagName' : '/tag/$tagName?p=$page';
  static String member(String username) => '/member/$username';
  static String notifications({int page = 1}) =>
      page <= 1 ? '/notifications' : '/notifications?p=$page';
  static String myTopics({int page = 1}) =>
      page <= 1 ? '/my/topics' : '/my/topics?p=$page';
  static String myFollowing({int page = 1}) =>
      page <= 1 ? '/my/following' : '/my/following?p=$page';
  static const String myNodes = '/my/nodes';
  static const String dailyMission = '/mission/daily';

  /// Topic form (`/new`) — scraped for `once`; `/new/{node}` preselects a node.
  /// The POST target is always `/new`.
  static String createTopicForm({String? node}) =>
      (node == null || node.isEmpty) ? '/new' : '/new/$node';
  static const String createTopicSubmit = '/new';

  static String appendForm(int topicId) => '/t/$topicId/append';

  // -------------------------------------------------------------- JSON API

  static const String apiHotTopics = '/api/topics/hot.json';
  static const String apiLatestTopics = '/api/topics/latest.json';

  /// `/api/nodes/list.json` now answers 400; `s2.json` is the live source and
  /// returns `{text, id, topics, aliases}` for ~1400 nodes (~150 KB).
  static const String apiNodesList = '/api/nodes/s2.json';

  /// Full public node directory (~1376 nodes / ~800 KB). Unlike `s2.json` each
  /// entry carries the numeric `id` **and** the slug, which is what resolves a
  /// sov2ex search hit's numeric `node` back to its real name.
  static const String apiNodesAll = '/api/nodes/all.json';
  static String apiNodeDetail(String name) => '/api/nodes/show.json?name=$name';
  static String apiNodeInfo(String nodeName) =>
      '/api/nodes/show.json?name=$nodeName';
  static String apiMemberInfo(String username) =>
      '/api/members/show.json?username=$username';

  // ------------------------------------------------------------ write ops

  static const String signIn = '/signin';
  static const String signInWithNext = '/signin?next=/';

  /// V2EX redirects here when too many sign-in attempts came from one IP
  /// ("You may need to wait up to 1 day"). Distinct from a valid session.
  static const String signInCooldown = '/signin/cooldown';
  static const String twoFactor = '/2fa?next=/mission/daily';
  static const String checkInPath = '/mission/daily/redeem';

  /// Sign in with Solana：`POST {signature, message, public_key}`，消息为
  /// `Sign in to V2EX: <unix 秒>`，签名 hex，公钥 base58（Solana 地址）。
  /// 拒绝时按状态码回 JSON `{"error": …}`（400 时间戳过期 / 401 签名无效 /
  /// 404 地址未绑定会员，verified live 2026-09-21）。
  static const String authSolana = '/auth/solana';

  /// Solana 登录帮助页 —— 钱包未绑定时引导用户去网页端绑定/注册。
  static const String solanaHelp = '/solana';

  /// Appends the session CSRF token as the `once` query parameter used by the
  /// GET/POST action endpoints (`/favorite/topic/{id}?once=…`, `…/thank/reply/
  /// {replyId}?once=…`). The token is URL-encoded because it is opaque to us.
  static String withOnce(String path, String once) {
    if (once.isEmpty) return path;
    final separator = path.contains('?') ? '&' : '?';
    return '$path${separator}once=${Uri.encodeQueryComponent(once)}';
  }

  /// Referer for topic-scoped write actions; V2EX validates it (`docs/12` §1).
  static String topicReferer(int topicId) => '$baseUrl/t/$topicId';

  static String reply(int topicId) => '/t/$topicId';
  static String append(int topicId) => '/t/$topicId/append';
  static String thankTopic(int topicId) => '/thank/topic/$topicId';
  static String thankReply(String replyId) => '/thank/reply/$replyId';
  static String favoriteTopic(int topicId) => '/favorite/topic/$topicId';
  static String unfavoriteTopic(int topicId) => '/unfavorite/topic/$topicId';
  static String ignoreTopic(int topicId) => '/ignore/topic/$topicId';
  static String unignoreTopic(int topicId) => '/unignore/topic/$topicId';
  static String ignoreReply(String replyId) => '/ignore/reply/$replyId';
  static String ignoreNode(String nodeId) => '/settings/ignore/node/$nodeId';
  static String upTopic(int topicId) => '/up/topic/$topicId';
  static String downTopic(int topicId) => '/down/topic/$topicId';
  static String captcha(String once, int nowMillis) =>
      '/_captcha?once=$once&now=$nowMillis';
}

/// Chinese literals scraped from pages.
///
/// These are inherently brittle — they are collected here (and covered by
/// fixture tests) rather than sprinkled through the parsers.
abstract final class V2exLiterals {
  // Topic state
  static const String favoriteCancel = '取消收藏';
  static const String thankedSent = '感谢已发送';
  static const String ignoreCancel = '取消忽略';

  // Feed
  static const String pinned = '置顶';
  static const String itemSeparator = '&nbsp;•&nbsp;';

  // Daily mission
  static const String consecutivePrefix = '已连续';

  // Anti-flood / error bodies
  static const String tooFrequent = '操作过于频繁';
  static const String pleaseSlowDown = '请不要频繁操作';

  /// True when a response body carries V2EX's anti-flood signal.
  static bool isRateLimited(String body) =>
      body.contains(tooFrequent) || body.contains(pleaseSlowDown);
}
