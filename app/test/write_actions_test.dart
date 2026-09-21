import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/home_tab.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/core/network/v2ex_endpoints.dart';
import 'package:mv2/core/parser/login_parser.dart';
import 'package:mv2/features/composer/application/draft_store.dart';
import 'package:mv2/features/topic/application/topic_actions.dart';
import 'package:mv2/features/topic/application/topic_providers.dart';
import 'package:mv2/shared/models/account_info.dart';
import 'package:mv2/shared/models/daily_mission.dart';
import 'package:mv2/shared/models/login_form.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/notification_page.dart';
import 'package:mv2/shared/models/publish_form.dart';
import 'package:mv2/shared/models/topic_detail.dart';
import 'package:mv2/shared/models/write_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every write call and lets a test decide each outcome. Read methods
/// are not exercised here and fail loudly if the controller ever reaches them.
class _FakeWriteApi implements V2exApi {
  final List<String> calls = <String>[];
  Future<V2WriteResult> Function()? onFavorite;
  Future<V2WriteResult> Function()? onUnfavorite;
  Future<V2WriteResult> Function()? onThankTopic;
  Future<V2WriteResult> Function()? onThankReply;

  Future<V2WriteResult> _ok() async => const V2WriteResult(success: true);

  @override
  Future<V2WriteResult> replyToTopic(int topicId, String content, String once) {
    calls.add('reply:$topicId:$once');
    return _ok();
  }

  @override
  Future<V2WriteResult> thankTopic(int topicId, String once) {
    calls.add('thank:$topicId:$once');
    return onThankTopic?.call() ?? _ok();
  }

  @override
  Future<V2WriteResult> thankReply(String replyId, String once) {
    calls.add('thankReply:$replyId:$once');
    return onThankReply?.call() ?? _ok();
  }

  @override
  Future<V2WriteResult> favoriteTopic(int topicId, String once) {
    calls.add('favorite:$topicId:$once');
    return onFavorite?.call() ?? _ok();
  }

  @override
  Future<V2WriteResult> unfavoriteTopic(int topicId, String once) {
    calls.add('unfavorite:$topicId:$once');
    return onUnfavorite?.call() ?? _ok();
  }

  @override
  Future<V2WriteResult> ignoreTopic(int topicId, String once) {
    calls.add('ignore:$topicId:$once');
    return _ok();
  }

  @override
  Future<V2WriteResult> unignoreTopic(int topicId, String once) {
    calls.add('unignore:$topicId:$once');
    return _ok();
  }

  @override
  Future<V2WriteResult> ignoreReply(String replyId, String once) {
    calls.add('ignoreReply:$replyId:$once');
    return _ok();
  }

  @override
  Future<V2WriteResult> appendTopic(int topicId, String content, String once) {
    calls.add('append:$topicId:$once');
    return _ok();
  }

  @override
  Future<V2WriteResult> ignoreNode(String nodeId, String once) {
    calls.add('ignoreNode:$nodeId:$once');
    return _ok();
  }

  // ----------------------------------------------------------- not exercised

  @override
  Future<List<V2Topic>> feed(HomeTab tab, {PacePriority priority = PacePriority.userRead}) => throw UnimplementedError();

  
  @override
  Future<({List<V2Topic> topics, DateTime fetchedAt})?> feedCached(HomeTab tab, {required Duration maxAge}) => throw UnimplementedError();

  @override
  Future<List<V2XnaEntry>> xna() => throw UnimplementedError();

  @override
  Future<V2TopicDetail> topicDetail(int topicId, {int page = 1}) =>
      throw UnimplementedError();

  @override
  Future<V2NodePage> nodePage(String nodeName, {int page = 1}) =>
      throw UnimplementedError();

  @override
  Future<List<V2Node>> nodes() => throw UnimplementedError();

  @override
  Future<NotificationPage> notifications({int page = 1}) =>
      throw UnimplementedError();

  @override
  Future<V2Profile?> member(String username) => throw UnimplementedError();

  @override
  Future<List<V2Topic>> searchTopics(
    String query, {
    int from = 0,
    String sort = 'sumup',
  }) => throw UnimplementedError();

  @override
  Future<List<V2User>> searchUsers(String query) => throw UnimplementedError();

  @override
  Future<V2AccountInfo?> currentUser() => throw UnimplementedError();

  @override
  Future<V2DailyMission> dailyMission() => throw UnimplementedError();

  @override
  Future<V2DailyMission> checkIn() => throw UnimplementedError();

  @override
  Future<V2LoginForm?> loginForm() => throw UnimplementedError();

  @override
  Future<List<int>> captchaImage(String captchaPath, {String? once}) =>
      throw UnimplementedError();

  @override
  Future<V2LoginResult> login({
    required V2LoginForm form,
    required String username,
    required String password,
    required String captcha,
  }) => throw UnimplementedError();

  @override
  Future<V2LoginResult> twoStep({
    required V2LoginForm form,
    required String code,
  }) => throw UnimplementedError();

  @override
  Future<V2SolanaLoginResult> loginWithSolana({
    required String publicKey,
    required String signature,
    required String message,
  }) => throw UnimplementedError();

  @override
  Future<V2TopicForm> topicForm({String? node}) => throw UnimplementedError();

  @override
  Future<V2PublishResult> publishTopic({
    required V2TopicForm form,
    required String nodeName,
    required String title,
    required String content,
  }) => throw UnimplementedError();
}

/// Replays canned responses and records the outgoing requests, mirroring the
/// transport test harness, so the write contract can be asserted offline.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _html(
  String body, {
  int status = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    body,
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      ...?headers,
    },
  );
}

Mv2HttpClient _clientWith(_FakeAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: V2exEndpoints.baseUrl,
      followRedirects: false,
      validateStatus: (status) => status != null && status < 400,
      headers: <String, String>{'User-Agent': V2exEndpoints.userAgent},
    ),
  )..httpClientAdapter = adapter;
  return Mv2HttpClient(dio, CookieJar());
}

V2TopicDetail _detail({String? once = 'tok'}) {
  return V2TopicDetail(
    topic: const V2Topic(
      id: 1,
      node: V2Node(key: 'programmer', name: '程序员', icon: Icons.code),
      title: '示例主题',
      author: V2User(username: 'rwecho'),
      createdAtLabel: '刚刚',
      replyCount: 0,
    ),
    once: once,
  );
}

ProviderContainer _container(_FakeWriteApi api, V2TopicDetail detail) {
  return ProviderContainer.test(
    overrides: [
      v2exApiProvider.overrideWithValue(api),
      topicDetailProvider.overrideWith((ref, args) async => detail),
    ],
  );
}

Future<TopicActionsController> _notifier(ProviderContainer container) async {
  await container.read(topicDetailProvider(const TopicDetailArgs(1)).future);
  return container.read(topicActionsProvider(1).notifier);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TopicActionsController', () {
    test('optimistic favourite rolls back and surfaces the error', () async {
      final api = _FakeWriteApi()
        ..onFavorite = (() async => const V2WriteResult(
          success: false,
          errors: <String>['收藏失败，请稍后再试'],
        ));
      final container = _container(api, _detail());
      final notifier = await _notifier(container);

      final pending = notifier.toggleFavorite();

      // Applied optimistically before the request settles.
      expect(container.read(topicActionsProvider(1)).favorited, isTrue);

      final failure = await pending;
      final state = container.read(topicActionsProvider(1));
      expect(state.favorited, isFalse, reason: 'must roll back');
      expect(failure, isA<ActionRejectedFailure>());
      expect(failure?.message, '收藏失败，请稍后再试');
      expect(state.errorMessage, '收藏失败，请稍后再试');
      expect(
        container
            .read(topicActionsProvider(1))
            .isInFlight(TopicActionsController.favoriteKey),
        isFalse,
      );
      expect(api.calls, <String>['favorite:1:tok']);
    });

    test('a double tap only sends one request', () async {
      final completer = Completer<V2WriteResult>();
      final api = _FakeWriteApi()..onFavorite = (() => completer.future);
      final container = _container(api, _detail());
      final notifier = await _notifier(container);

      final first = notifier.toggleFavorite();
      final second = notifier.toggleFavorite();
      completer.complete(const V2WriteResult(success: true));

      expect(await first, isNull);
      expect(await second, isNull);
      expect(api.calls, hasLength(1));
      expect(container.read(topicActionsProvider(1)).favorited, isTrue);
    });

    test('missing once sends no request and reports AuthFailure', () async {
      final api = _FakeWriteApi();
      final container = _container(api, _detail(once: null));
      final notifier = await _notifier(container);

      final failure = await notifier.toggleFavorite();

      expect(api.calls, isEmpty);
      expect(failure, isA<AuthFailure>());
      final state = container.read(topicActionsProvider(1));
      expect(state.failure, isA<AuthFailure>());
      expect(state.authRequired, isTrue);
      expect(
        state.favorited,
        isNull,
        reason: 'no optimistic change without a token',
      );
    });

    test('RateLimitFailure surfaces its own message and rolls back', () async {
      final api = _FakeWriteApi()
        ..onFavorite = (() async => throw const RateLimitFailure());
      final container = _container(api, _detail());
      final notifier = await _notifier(container);

      final failure = await notifier.toggleFavorite();

      expect(failure, isA<RateLimitFailure>());
      expect(failure?.message, '操作过于频繁，请稍后再试。');
      expect(container.read(topicActionsProvider(1)).favorited, isFalse);
      expect(
        container.read(topicActionsProvider(1)).errorMessage,
        '操作过于频繁，请稍后再试。',
      );
    });

    test('reply thanks are tracked per reply id', () async {
      final api = _FakeWriteApi();
      final container = _container(api, _detail());
      final notifier = await _notifier(container);

      final failure = await notifier.thankReply('18074386');

      expect(failure, isNull);
      expect(api.calls, <String>['thankReply:18074386:tok']);
      expect(
        container.read(topicActionsProvider(1)).thankedReplies,
        contains('18074386'),
      );
    });

    test('topic thanks are one-way (a second tap is a no-op)', () async {
      final api = _FakeWriteApi();
      final container = _container(api, _detail());
      final notifier = await _notifier(container);

      await notifier.thankTopic();
      await notifier.thankTopic();

      expect(api.calls, <String>['thank:1:tok']);
      expect(container.read(topicActionsProvider(1)).thanked, isTrue);
    });

    test('ignore toggles to unignore on the second call', () async {
      final api = _FakeWriteApi();
      final container = _container(api, _detail());
      final notifier = await _notifier(container);

      await notifier.toggleIgnore();
      expect(container.read(topicActionsProvider(1)).ignored, isTrue);

      await notifier.toggleIgnore();
      expect(container.read(topicActionsProvider(1)).ignored, isFalse);
      expect(api.calls, <String>['ignore:1:tok', 'unignore:1:tok']);
    });
  });

  group('V2WriteResult / problem parsing', () {
    test('div.problem li messages become V2WriteResult errors', () {
      const html =
          '<div class="problem"><ul><li>回复内容不能为空</li>'
          '<li>你没有权限执行此操作</li></ul></div>';

      final errors = LoginFormParser.parseErrors(html);
      final result = V2WriteResult(success: false, errors: errors);

      expect(result.success, isFalse);
      expect(result.errors, <String>['回复内容不能为空', '你没有权限执行此操作']);
    });

    test('RemoteV2exApi maps a 200 problem page to errors', () async {
      final adapter = _FakeAdapter(
        (_) => _html('<div class="problem"><ul><li>回复内容不能为空</li></ul></div>'),
      );
      final api = RemoteV2exApi(_clientWith(adapter));

      final result = await api.replyToTopic(123, 'hi', 'tok');

      expect(result.success, isFalse);
      expect(result.errors, <String>['回复内容不能为空']);
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/t/123');
      expect(request.headers['Referer'], '${V2exEndpoints.baseUrl}/t/123');
    });

    test('RemoteV2exApi maps a 302 to success', () async {
      final adapter = _FakeAdapter(
        (_) => _html(
          '',
          status: 302,
          headers: <String, List<String>>{
            'location': <String>['/t/123'],
          },
        ),
      );
      final api = RemoteV2exApi(_clientWith(adapter));

      final result = await api.replyToTopic(123, 'hi', 'tok');

      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
    });

    test(
      'content writes carry the device UA, other writes keep the mobile UA',
      () async {
        // V2EX derives the public `via <platform>` label from the posting
        // request's UA, so reply/append/publish present the real device while
        // everything else stays on the stable mobile read UA.
        final adapter = _FakeAdapter(
          (_) => _html(
            '',
            status: 302,
            headers: <String, List<String>>{
              'location': <String>['/t/123'],
            },
          ),
        );
        final api = RemoteV2exApi(
          _clientWith(adapter),
          writeUa: () => V2exEndpoints.iPhoneWriteUserAgent,
        );

        await api.replyToTopic(123, 'hi', 'tok');
        await api.appendTopic(123, '补充一点', 'tok');
        await api.publishTopic(
          form: const V2TopicForm(once: 'tok'),
          nodeName: 'programmer',
          title: '标题',
          content: '正文',
        );
        await api.favoriteTopic(123, 'tok');

        final uas = adapter.requests
            .map((request) => request.headers['User-Agent'])
            .toList();
        expect(uas[0], V2exEndpoints.iPhoneWriteUserAgent); // POST /t/123
        expect(uas[1], V2exEndpoints.iPhoneWriteUserAgent); // POST append
        expect(uas[2], V2exEndpoints.iPhoneWriteUserAgent); // POST /new
        expect(uas[3], V2exEndpoints.userAgent); // GET favourite
      },
    );

    test('favourite is a GET carrying the once token', () async {
      final adapter = _FakeAdapter(
        (_) => _html(
          '',
          status: 302,
          headers: <String, List<String>>{
            'location': <String>['/t/123'],
          },
        ),
      );
      final api = RemoteV2exApi(_clientWith(adapter));

      final result = await api.favoriteTopic(123, 'tok');

      expect(result.success, isTrue);
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/favorite/topic/123');
      expect(request.uri.query, 'once=tok');
    });
  });

  group('RemoteV2exApi.loginForm', () {
    test('maps the /signin/cooldown redirect to a RateLimitFailure', () async {
      final adapter = _FakeAdapter(
        (_) => _html(
          '',
          status: 302,
          headers: <String, List<String>>{
            'location': <String>['/signin/cooldown'],
          },
        ),
      );
      final api = RemoteV2exApi(_clientWith(adapter));

      await expectLater(
        api.loginForm(),
        throwsA(
          isA<RateLimitFailure>().having(
            (failure) => failure.message,
            'message',
            contains('过于频繁'),
          ),
        ),
      );
    });

    test('any other redirect still means the session is already valid', () async {
      final adapter = _FakeAdapter(
        (_) => _html(
          '',
          status: 302,
          headers: <String, List<String>>{
            'location': <String>['/'],
          },
        ),
      );
      final api = RemoteV2exApi(_clientWith(adapter));

      expect(await api.loginForm(), isNull);
    });
  });

  group('DraftStore', () {
    test('round-trips and clears a topic draft', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = DraftStore();
      final key = DraftStore.topicKey(42);

      expect(await store.read(key), isNull);

      await store.write(key, '一段草稿');
      expect(await store.read(key), '一段草稿');

      await store.clear(key);
      expect(await store.read(key), isNull);
    });

    test('whitespace-only drafts are removed instead of persisted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = DraftStore();
      final key = DraftStore.topicKey(7);

      await store.write(key, '   ');
      expect(await store.read(key), isNull);
    });
  });
}
