import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/parser/thanks_parser.dart';
import 'package:mv2/features/topic/application/topic_actions.dart';
import 'package:mv2/features/topic/application/topic_providers.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/topic_detail.dart';
import 'package:mv2/shared/models/write_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// V2EX rotates the session `once` after a write and hands the new value back
/// in the `/thank/*` JSON. Without reusing it the **second** action in a row is
/// rejected.
class _RotatingApi extends FixtureV2exApi {
  _RotatingApi() : super(latency: Duration.zero);

  final List<String> replyThanksTokens = <String>[];

  @override
  Future<V2TopicDetail> topicDetail(int topicId, {int page = 1}) async =>
      _detail('base-token');

  @override
  Future<V2WriteResult> thankReply(String replyId, String once) async {
    replyThanksTokens.add(once);
    return V2WriteResult(success: true, once: 'rotated-$replyId');
  }
}

/// Rejects the first write like V2EX does when the session `once` was rotated
/// by another page render, then accepts the re-scraped token.
class _CsrfRetryApi extends FixtureV2exApi {
  _CsrfRetryApi() : super(latency: Duration.zero);

  final List<String> tokens = <String>[];
  int _render = 0;

  @override
  Future<V2TopicDetail> topicDetail(int topicId, {int page = 1}) async {
    _render++;
    return _detail('page-$_render');
  }

  @override
  Future<V2WriteResult> thankReply(String replyId, String once) async {
    tokens.add(once);
    if (tokens.length == 1) {
      return const V2WriteResult(
        success: false,
        errors: <String>['CSRF 校验失败，请刷新页面后重试'],
      );
    }
    return const V2WriteResult(success: true);
  }
}

/// Rejects the first write with a message that does **not** match the
/// once-failure heuristic, then accepts the re-scraped token. Regression:
/// favourite/ignore answer `302` with no `once`, so the next write can be
/// rejected without any recognisable "once" text.
class _GenericRejectApi extends FixtureV2exApi {
  _GenericRejectApi() : super(latency: Duration.zero);

  final List<String> tokens = <String>[];
  int _render = 0;

  @override
  Future<V2TopicDetail> topicDetail(int topicId, {int page = 1}) async {
    _render++;
    return _detail('page-$_render');
  }

  @override
  Future<V2WriteResult> thankTopic(int topicId, String once) async {
    tokens.add(once);
    if (tokens.length == 1) {
      return const V2WriteResult(
        success: false,
        errors: <String>['操作过于频繁，请稍后再试'],
      );
    }
    return const V2WriteResult(success: true);
  }
}

class _RateLimitedApi extends FixtureV2exApi {
  _RateLimitedApi() : super(latency: Duration.zero);

  final List<String> tokens = <String>[];

  @override
  Future<V2TopicDetail> topicDetail(int topicId, {int page = 1}) async =>
      _detail('page-1');

  @override
  Future<V2WriteResult> thankTopic(int topicId, String once) async {
    tokens.add(once);
    throw const RateLimitFailure();
  }
}

V2TopicDetail _detail(String once) => V2TopicDetail(
  topic: const V2Topic(
    id: 1,
    node: V2Node(key: 'programmer', name: '程序员', icon: Icons.code),
    title: '标题',
    author: V2User(username: 'someone'),
    createdAtLabel: '刚刚',
    replyCount: 0,
  ),
  once: once,
);

ProviderContainer _container(V2exApi api) => ProviderContainer(
  overrides: [
    v2exApiProvider.overrideWithValue(api),
    // Delegate to the mock instead of the real provider body: the real one
    // records history (Drift/platform channels), which leaks past a plain
    // `test()` body. `_refreshOnce` calls the API directly, so the token
    // sequence stays consistent between the page load and the re-scrape.
    topicDetailProvider.overrideWith(
      (ref, args) async => api.topicDetail(args.topicId, page: args.page),
    ),
  ],
);

Future<TopicActionsController> _controller(ProviderContainer container) async {
  await container.read(topicDetailProvider(const TopicDetailArgs(1)).future);
  return container.read(topicActionsProvider(1).notifier);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('ThanksParser exposes the rotated once', () {
    final result = ThanksParser.parse(
      '{"success":true,"once":74158,"message":""}',
    );
    expect(result.success, isTrue);
    expect(result.once, '74158');
  });

  test('a second thank reuses the token returned by the first', () async {
    final api = _RotatingApi();
    final container = _container(api);
    addTearDown(container.dispose);

    final controller = await _controller(container);
    final first = await controller.thankReply('r1');
    final second = await controller.thankReply('r2');

    expect(first, isNull, reason: 'first thank uses the page token');
    expect(second, isNull, reason: 'second thank uses the rotated token');
    expect(api.replyThanksTokens, <String>['base-token', 'rotated-r1']);
  });

  test('a CSRF rejection re-scrapes the page and retries once', () async {
    final api = _CsrfRetryApi();
    final container = _container(api);
    addTearDown(container.dispose);

    final controller = await _controller(container);
    final failure = await controller.thankReply('r1');

    expect(failure, isNull, reason: 'the retry with the fresh token succeeds');
    expect(api.tokens, <String>['page-1', 'page-2']);
  });

  test(
    'an unrecognised rejection still retries once with a fresh token',
    () async {
      final api = _GenericRejectApi();
      final container = _container(api);
      addTearDown(container.dispose);

      final controller = await _controller(container);
      final failure = await controller.thankTopic();

      expect(failure, isNull, reason: 'the retry recovers');
      expect(api.tokens, <String>['page-1', 'page-2']);
    },
  );

  test('a rate limit is not retried', () async {
    final api = _RateLimitedApi();
    final container = _container(api);
    addTearDown(container.dispose);

    final controller = await _controller(container);
    final failure = await controller.thankTopic();

    expect(failure, isA<RateLimitFailure>());
    expect(api.tokens, <String>['page-1'], reason: 'no retry on rate limit');
  });
}
