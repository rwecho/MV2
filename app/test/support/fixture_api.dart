import 'dart:io';

import 'package:mv2/core/data/home_tab.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/parser/feed_parser.dart';
import 'package:mv2/core/parser/member_parser.dart';
import 'package:mv2/core/parser/node_parser.dart';
import 'package:mv2/core/parser/notification_parser.dart';
import 'package:mv2/core/parser/topic_parser.dart';
import 'package:mv2/core/parser/xna_parser.dart';
import 'package:mv2/shared/models/account_info.dart';
import 'package:mv2/shared/models/daily_mission.dart';
import 'package:mv2/shared/models/login_form.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/notification_page.dart';
import 'package:mv2/shared/models/publish_form.dart';
import 'package:mv2/shared/models/topic_detail.dart';
import 'package:mv2/shared/models/write_result.dart';

/// Offline V2EX data source used **by tests only**.
///
/// Lives under `test/support/` so no fixture code or sample HTML ships in the
/// app: `lib/` talks to the real site through `RemoteV2exApi`, and when the
/// network fails the UI surfaces the error instead of falling back to fake
/// content. Every payload here goes through the same parsers as the remote
/// implementation, so tests still exercise the real parsing code.
class FixtureV2exApi implements V2exApi {
  FixtureV2exApi({this.latency = const Duration(milliseconds: 250)});

  final Duration latency;

  static const String _home = 'assets/fixtures/feed_home.html';
  static const String _xna = 'assets/fixtures/xna.html';
  static const String _topic = 'assets/fixtures/topic_detail.html';
  static const String _node = 'assets/fixtures/node_page.html';
  static const String _notifications =
      'assets/fixtures/notifications_signed_in.html';
  static const String _member = 'assets/fixtures/member_livid.html';

  /// Tiny stand-in for `/api/nodes/all.json` so the fixture search path can
  /// resolve a numeric node id exactly like the remote one. Real entries
  /// captured from the live all-nodes payload (2026-09-11).
  static final Map<int, V2Node> _nodeDirectory = NodeParser.parseAllNodesJson(
    <dynamic>[
      <String, dynamic>{
        'id': 864,
        'name': 'promotions',
        'title': '推广',
        'topics': 14043,
        'aliases': <String>[],
      },
      <String, dynamic>{
        'id': 300,
        'name': 'programmer',
        'title': '程序员',
        'topics': 73280,
        'aliases': <String>['developer'],
      },
      <String, dynamic>{
        'id': 17,
        'name': 'create',
        'title': '分享创造',
        'topics': 36535,
        'aliases': <String>[],
      },
      <String, dynamic>{
        'id': 69,
        'name': 'all4all',
        'title': '二手交易',
        'topics': 147794,
        'aliases': <String>[],
      },
    ],
  );

  /// Resolves a node whose key is a raw numeric id against [_nodeDirectory];
  /// an already-slugged node is returned untouched.
  static V2Node _resolveNode(V2Node node) {
    final id = node.nodeId ?? int.tryParse(node.key);
    return (id == null ? null : _nodeDirectory[id]) ?? node;
  }

  /// Resolves fixture files from the package root (`flutter test` runs with
  /// the package root as the working directory), NOT from the asset bundle —
  /// `assets/fixtures/` is no longer declared in `pubspec.yaml` so nothing
  /// sample-shaped ships with the app.
  ///
  /// The read is **synchronous** on purpose: `testWidgets` runs inside a
  /// FakeAsync zone that never completes real async file I/O, so awaiting
  /// `readAsString()` would hang the test until its timeout.
  Future<String> _load(String relativePath) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return File(
      '${Directory.current.path}${Platform.pathSeparator}$relativePath',
    ).readAsStringSync();
  }

  @override
  Future<List<V2Topic>> feed(HomeTab tab) async {
    // The aggregator is not a topic list; `HomeFeedPage` routes it to [xna].
    if (tab.isAggregator) return const <V2Topic>[];
    final topics = FeedParser.parseTopicList(await _load(_home));
    // The bundled capture is one page, so reverse it for a couple of tabs to
    // make the offline tab switch visibly different while testing.
    return switch (tab) {
      HomeTab.hot ||
      HomeTab.creative ||
      HomeTab.jobs => topics.reversed.toList(growable: false),
      _ => topics,
    };
  }

  @override
  Future<List<V2XnaEntry>> xna() async {
    return XnaParser.parse(await _load(_xna));
  }

  @override
  Future<V2TopicDetail> topicDetail(int topicId, {int page = 1}) async {
    final html = await _load(_topic);
    return TopicParser.parse(html, topicId: topicId);
  }

  @override
  Future<V2NodePage> nodePage(String nodeName, {int page = 1}) async {
    final html = await _load(_node);
    return NodeParser.parseNodePage(html, nodeName: nodeName);
  }

  @override
  Future<V2LoginForm?> loginForm() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return null;
  }

  @override
  Future<List<int>> captchaImage(String captchaPath, {String? once}) async {
    throw const NetworkFailure(message: '测试数据源无法加载验证码。');
  }

  @override
  Future<V2LoginResult> login({
    required V2LoginForm form,
    required String username,
    required String password,
    required String captcha,
  }) async {
    return const V2LoginResult(
      success: false,
      errors: <String>['测试数据源无法登录。'],
    );
  }

  @override
  Future<V2LoginResult> twoStep({
    required V2LoginForm form,
    required String code,
  }) async {
    return const V2LoginResult(success: false, errors: <String>['测试数据源。']);
  }

  /// Offline fixture for `/new`: a syntactically valid form so the publish
  /// page can be driven without a session.
  @override
  Future<V2TopicForm> topicForm({String? node}) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return V2TopicForm(
      once: 'fixture-once',
      defaultNode: node ?? 'programmer',
      nodeOptions: const <V2NodeOption>[
        V2NodeOption(name: 'programmer', title: '程序员'),
        V2NodeOption(name: 'create', title: '分享创造'),
        V2NodeOption(name: 'qna', title: '问与答'),
      ],
    );
  }

  /// Offline publishing never reaches the network: it validates the same
  /// fields V2EX does and reports success so the post-submit flow is
  /// exercisable.
  @override
  Future<V2PublishResult> publishTopic({
    required V2TopicForm form,
    required String nodeName,
    required String title,
    required String content,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final problems = <String>[
      if (title.trim().isEmpty) '主题标题不能为空',
      if (content.trim().isEmpty) '主题内容不能为空',
      if (nodeName.trim().isEmpty) '请选择节点',
    ];
    if (problems.isNotEmpty) {
      return V2PublishResult(success: false, errors: problems);
    }
    return const V2PublishResult(success: true);
  }

  @override
  Future<V2AccountInfo?> currentUser() async => null;

  @override
  Future<V2DailyMission> dailyMission() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return const V2DailyMission(
      continuousDaysLabel: '已连续登录 1 天',
      redeemPath: null,
      alreadyCheckedIn: true,
    );
  }

  @override
  Future<V2DailyMission> checkIn() => dailyMission();

  @override
  Future<List<V2Node>> nodes() async {
    // The public node list is a JSON endpoint; keep a small inline sample so
    // no extra asset is needed.
    return NodeParser.parseNodesJson(<dynamic>[
      <String, dynamic>{
        'name': 'programmer',
        'title': '程序员',
        'topics': 12400,
        'aliases': <String>['编程', '技术栈', '职业发展'],
      },
      <String, dynamic>{
        'name': 'create',
        'title': '分享创造',
        'topics': 8700,
        'aliases': <String>['独立项目', '产品', '创意'],
      },
      <String, dynamic>{
        'name': 'ai',
        'title': 'AI',
        'topics': 15200,
        'aliases': <String>['大语言模型', 'AI 应用', '提示工程'],
      },
      <String, dynamic>{
        'name': 'apple',
        'title': 'Apple',
        'topics': 6800,
        'aliases': <String>['iOS', 'macOS', 'Apple 生态'],
      },
      <String, dynamic>{
        'name': 'qna',
        'title': '问与答',
        'topics': 9100,
        'aliases': <String>['技术问答', '产品使用', '生活经验'],
      },
      <String, dynamic>{
        'name': 'idev',
        'title': '独立开发',
        'topics': 5300,
        'aliases': <String>['独立开发', '产品', '增长'],
      },
    ]);
  }

  @override
  Future<NotificationPage> notifications({int page = 1}) async {
    final html = await _load(_notifications);
    final parsed = NotificationParser.parse(html);
    // The bundled fixture is a single signed-in page; pinning pagination keeps
    // infinite scroll from re-appending the same rows.
    return parsed.copyWith(
      pagination: V2Pagination(current: page, maximum: page),
    );
  }

  @override
  Future<V2Profile?> member(String username) async {
    final html = await _load(_member);
    final parsed = MemberParser.parseMemberPage(html);
    if (parsed == null) return null;
    // The bundled capture is Livid's page; synthesise any other username on
    // top of it so the profile UI still has data offline.
    if (parsed.user.username == username) return parsed;
    return V2Profile(
      user: V2User(
        username: username,
        avatarUrl: parsed.user.avatarUrl,
        id: parsed.user.id,
        tagline: parsed.user.tagline,
      ),
      topicCount: parsed.topicCount,
      replyCount: parsed.replyCount,
      favoriteCount: parsed.favoriteCount,
      recentTopics: parsed.recentTopics,
    );
  }

  @override
  Future<List<V2Topic>> searchTopics(
    String query, {
    int from = 0,
    String sort = 'sumup',
  }) async {
    // Offline stand-in: filter the bundled feed fixture by title/author and
    // hand back the requested slice, so the search UI still renders its real
    // ResultCard/TopicItem path without network access.
    final html = await _load(_home);
    final topics = FeedParser.parseTopicList(html);
    final term = query.trim().toLowerCase();
    final matched = term.isEmpty
        ? topics
        : topics
              .where(
                (topic) =>
                    topic.title.toLowerCase().contains(term) ||
                    topic.author.username.toLowerCase().contains(term),
              )
              .toList(growable: false);
    final resolved = matched
        .map((topic) => topic.copyWith(node: _resolveNode(topic.node)))
        .toList(growable: false);
    if (from <= 0) return resolved;
    if (from >= resolved.length) return const <V2Topic>[];
    return resolved.sublist(from);
  }

  @override
  Future<List<V2User>> searchUsers(String query) async {
    // Distinct authors from the bundled feed fixture, filtered by username.
    final html = await _load(_home);
    final term = query.trim().toLowerCase();
    final users = <V2User>[];
    final seen = <String>{};
    for (final topic in FeedParser.parseTopicList(html)) {
      final username = topic.author.username;
      if (term.isNotEmpty && !username.toLowerCase().contains(term)) continue;
      if (seen.add(username)) users.add(topic.author);
    }
    return users;
  }

  // ---------------------------------------------------------- write actions

  /// The offline surface refuses every write. It must never report success —
  /// a fake "sent" would mislead the UI and the test asserting on it.
  static const V2WriteResult _offlineWrite = V2WriteResult(
    success: false,
    errors: <String>['测试数据源无法执行写操作。'],
  );

  Future<V2WriteResult> _offlineWriteResult() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return _offlineWrite;
  }

  @override
  Future<V2WriteResult> replyToTopic(
    int topicId,
    String content,
    String once,
  ) => _offlineWriteResult();

  @override
  Future<V2WriteResult> thankTopic(int topicId, String once) =>
      _offlineWriteResult();

  @override
  Future<V2WriteResult> thankReply(String replyId, String once) =>
      _offlineWriteResult();

  @override
  Future<V2WriteResult> favoriteTopic(int topicId, String once) =>
      _offlineWriteResult();

  @override
  Future<V2WriteResult> unfavoriteTopic(int topicId, String once) =>
      _offlineWriteResult();

  @override
  Future<V2WriteResult> ignoreTopic(int topicId, String once) =>
      _offlineWriteResult();

  @override
  Future<V2WriteResult> unignoreTopic(int topicId, String once) =>
      _offlineWriteResult();

  @override
  Future<V2WriteResult> ignoreReply(String replyId, String once) =>
      _offlineWriteResult();

  @override
  Future<V2WriteResult> appendTopic(int topicId, String content, String once) =>
      _offlineWriteResult();

  @override
  Future<V2WriteResult> ignoreNode(String nodeId, String once) =>
      _offlineWriteResult();
}
