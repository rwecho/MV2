import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/auth/data/auth_store.dart';
import 'package:mv2/features/auth/domain/auth_session.dart';
import 'package:mv2/features/composer/application/publish_providers.dart';
import 'package:mv2/shared/models/publish_form.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fixture_api.dart';

/// In-memory session store so the auth controller never touches the keychain.
class _MemoryAuthStore extends AuthStore {
  AuthSession? session;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

ProviderContainer _container() {
  return ProviderContainer.test(
    overrides: [
      authStoreProvider.overrideWithValue(_MemoryAuthStore()),
      // The fixture API is deterministic and shares the same parser contract.
      v2exApiProvider.overrideWithValue(FixtureV2exApi(latency: Duration.zero)),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('load scrapes the form and preselects the default node', () async {
    final container = _container();

    await container.read(publishProvider.notifier).load();

    final state = container.read(publishProvider);
    expect(state.loading, isFalse);
    expect(state.form, isNotNull);
    expect(state.nodeSlug, 'programmer');
    expect(state.nodeTitle, '程序员');
    expect(state.failure, isNull);
  });

  test('the URL node wins over the form default', () async {
    final container = _container();

    await container.read(publishProvider.notifier).load(initialNode: 'ai');

    final state = container.read(publishProvider);
    expect(state.nodeSlug, 'ai');
  });

  test(
    'an incomplete draft cannot be submitted and reports problems',
    () async {
      final container = _container();
      await container.read(publishProvider.notifier).load();

      final ok = await container.read(publishProvider.notifier).submit();

      expect(ok, isFalse);
      expect(container.read(publishProvider).problems, isNotEmpty);
      expect(container.read(publishProvider).submitting, isFalse);
    },
  );

  test('a complete draft publishes and clears the draft flag', () async {
    final container = _container();
    final notifier = container.read(publishProvider.notifier);
    await notifier.load();
    notifier
      ..setTitle('Flutter 迁移记录')
      ..setContent('正文内容');

    expect(container.read(publishProvider).canSubmit, isTrue);
    final ok = await notifier.submit();

    expect(ok, isTrue);
    final state = container.read(publishProvider);
    expect(state.problems, isEmpty);
    expect(state.draftSaved, isFalse);
    expect(state.submitting, isFalse);
  });

  test('the draft is written to storage after the debounce', () async {
    final container = _container();
    final notifier = container.read(publishProvider.notifier);
    await notifier.load();
    notifier
      ..setTitle('草稿标题')
      ..setContent('草稿正文');

    expect(container.read(publishProvider).draftSaved, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(container.read(publishProvider).draftSaved, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mv2.publishDraft'), contains('草稿标题'));
  });

  test('load hydrates a stored draft', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mv2.publishDraft': jsonEncode(<String, String?>{
        'title': '上次的标题',
        'content': '上次的正文',
        'nodeSlug': 'create',
        'nodeTitle': '分享创造',
      }),
    });
    final container = _container();

    await container.read(publishProvider.notifier).load();

    final state = container.read(publishProvider);
    expect(state.title, '上次的标题');
    expect(state.content, '上次的正文');
    expect(state.nodeSlug, 'create');
    expect(state.draftSaved, isTrue);
  });

  test(
    'selectNode updates the target and togglePreview flips the pane',
    () async {
      final container = _container();
      final notifier = container.read(publishProvider.notifier);
      await notifier.load();

      notifier.selectNode('apple', 'Apple');
      expect(container.read(publishProvider).nodeSlug, 'apple');
      expect(container.read(publishProvider).nodeTitle, 'Apple');

      notifier.togglePreview();
      expect(container.read(publishProvider).preview, isTrue);
      notifier.togglePreview();
      expect(container.read(publishProvider).preview, isFalse);
    },
  );

  test('a route node overrides the stored draft label', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mv2.publishDraft': jsonEncode(<String, String?>{
        'title': '旧标题',
        'content': '旧正文',
        'nodeSlug': 'create',
        'nodeTitle': '分享创造',
      }),
    });
    final container = _container();

    await container.read(publishProvider.notifier).load(initialNode: 'ai');

    final state = container.read(publishProvider);
    expect(state.nodeSlug, 'ai');
    expect(state.nodeTitle, isNot('分享创造'));
  });

  test('editing clears the previous problem messages', () async {
    final container = _container();
    final notifier = container.read(publishProvider.notifier);
    await notifier.load();
    await notifier.submit();
    expect(container.read(publishProvider).problems, isNotEmpty);

    notifier.setTitle('标题');

    expect(container.read(publishProvider).problems, isEmpty);
  });

  test('an auth failure from /new surfaces the signed-out state', () async {
    final container = ProviderContainer.test(
      overrides: [
        authStoreProvider.overrideWithValue(_MemoryAuthStore()),
        v2exApiProvider.overrideWithValue(_AuthFailingApi()),
      ],
    );

    await container.read(publishProvider.notifier).load();

    final state = container.read(publishProvider);
    expect(state.signedOut, isTrue);
    expect(state.loading, isFalse);
  });

  test('a stale once is re-scraped and the publish retried once', () async {
    final api = _StaleTokenApi(invalidTimes: 1);
    final container = ProviderContainer.test(
      overrides: [
        authStoreProvider.overrideWithValue(_MemoryAuthStore()),
        v2exApiProvider.overrideWithValue(api),
      ],
    );
    final notifier = container.read(publishProvider.notifier);
    await notifier.load();
    notifier
      ..setTitle('标题')
      ..setContent('正文');

    final ok = await notifier.submit();

    expect(ok, isTrue);
    // One scrape for the page open, one refresh after the rejection.
    expect(api.formCalls, 2);
    expect(api.publishCalls, 2);
    expect(container.read(publishProvider).problems, isEmpty);
  });

  test('a permanently stale once is not retried more than once', () async {
    final api = _StaleTokenApi(invalidTimes: 99);
    final container = ProviderContainer.test(
      overrides: [
        authStoreProvider.overrideWithValue(_MemoryAuthStore()),
        v2exApiProvider.overrideWithValue(api),
      ],
    );
    final notifier = container.read(publishProvider.notifier);
    await notifier.load();
    notifier
      ..setTitle('标题')
      ..setContent('正文');

    final ok = await notifier.submit();

    expect(ok, isFalse);
    // The first attempt plus a single retry — never a loop.
    expect(api.publishCalls, 2);
    expect(container.read(publishProvider).problems, isNotEmpty);
    expect(container.read(publishProvider).submitting, isFalse);
  });
}

/// Rejects the first [invalidTimes] publishes with a stale-token signal, then
/// succeeds; counts both endpoints so the retry policy is observable.
class _StaleTokenApi extends FixtureV2exApi {
  _StaleTokenApi({required this.invalidTimes}) : super(latency: Duration.zero);

  final int invalidTimes;
  int formCalls = 0;
  int publishCalls = 0;

  @override
  Future<V2TopicForm> topicForm({String? node}) async {
    formCalls++;
    return V2TopicForm(once: 'once-$formCalls', defaultNode: 'programmer');
  }

  @override
  Future<V2PublishResult> publishTopic({
    required V2TopicForm form,
    required String nodeName,
    required String title,
    required String content,
  }) async {
    publishCalls++;
    if (publishCalls <= invalidTimes) {
      return const V2PublishResult(success: false, invalidToken: true);
    }
    return const V2PublishResult(success: true);
  }
}

class _AuthFailingApi extends FixtureV2exApi {
  _AuthFailingApi() : super(latency: Duration.zero);

  @override
  Future<V2TopicForm> topicForm({String? node}) async {
    throw const AuthFailure();
  }
}
