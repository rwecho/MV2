import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/app/session_cache_refresh.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/core/storage/cache_database.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/auth/data/auth_store.dart';
import 'package:mv2/features/auth/domain/auth_session.dart';
import 'package:mv2/features/composer/presentation/reply_composer_page.dart';
import 'package:mv2/features/topic/application/topic_providers.dart';
import 'package:mv2/shared/models/account_info.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/topic_detail.dart';
import 'package:mv2/ui/primitives/mv2_buttons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A topic page fetched anonymously carries **no** `once` token, and the detail
/// provider is long-lived. Signing in used to leave that cached anonymous copy
/// in place, so the reply composer's 发送 button never became usable.
class _SessionApi extends FixtureV2exApi {
  _SessionApi() : super(latency: Duration.zero);

  bool signedIn = false;
  int detailCalls = 0;

  @override
  Future<V2TopicDetail> topicDetail(int topicId, {int page = 1}) async {
    detailCalls++;
    final detail = await super.topicDetail(topicId, page: page);
    if (signedIn) return detail.copyWith(once: 'fresh-once');
    // `copyWith(once: null)` keeps the old value, so build the anonymous copy
    // explicitly — that is what the real signed-out HTML yields.
    return V2TopicDetail(
      topic: detail.topic,
      contentHtml: detail.contentHtml,
      supplements: detail.supplements,
      tags: detail.tags,
      statsLabel: detail.statsLabel,
      replyStatsLabel: detail.replyStatsLabel,
      favorited: detail.favorited,
      thanked: detail.thanked,
      ignored: detail.ignored,
      once: null,
      pagination: detail.pagination,
      replies: detail.replies,
    );
  }

  @override
  Future<V2AccountInfo?> currentUser() async => signedIn ? _account() : null;
}

V2AccountInfo _account() => const V2AccountInfo(
  user: V2User(username: 'rwecho', id: 94728),
  notifications: '0',
  moneyGold: '0',
  moneySilver: '0',
  moneyBronze: '0',
);

/// In-memory session store so the controller never touches the keychain.
class _MemoryAuthStore extends AuthStore {
  AuthSession? session;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

ProviderContainer _container(_SessionApi api) {
  return ProviderContainer(
    overrides: [
      v2exApiProvider.overrideWithValue(api),
      authStoreProvider.overrideWithValue(_MemoryAuthStore()),
      httpClientProvider.overrideWithValue(Mv2HttpClient(Dio(), CookieJar())),
      // `topicDetailProvider` records 浏览历史 through the Drift store, whose
      // default `driftDatabase(...)` factory opens a `path_provider`-backed
      // file. That plugin is not registered under `flutter test`, so running
      // this file *alone* failed with `MissingPluginException
      // getTemporaryDirectory`. An in-memory executor keeps the test
      // order-independent without weakening any assertion.
      cacheDatabaseProvider.overrideWith((ref) {
        final database = CacheDatabase(NativeDatabase.memory());
        ref.onDispose(database.close);
        return database;
      }),
    ],
  );
}

bool _sendEnabled(WidgetTester tester) => tester
    .widget<Mv2TextButton>(find.widgetWithText(Mv2TextButton, '发送'))
    .enabled;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('signing in invalidates the anonymous topic detail', () async {
    final api = _SessionApi();
    final container = _container(api);
    addTearDown(container.dispose);
    // Keep the root invalidation listener alive for the test.
    final subscription = container.listen(
      sessionCacheRefreshProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    final anonymous = await container.read(
      topicDetailProvider(const TopicDetailArgs(1)).future,
    );
    expect(anonymous.once, isNull);
    expect(api.detailCalls, 1);

    api.signedIn = true;
    await container.read(authControllerProvider.notifier).refreshAccount();

    final signedIn = await container.read(
      topicDetailProvider(const TopicDetailArgs(1)).future,
    );
    expect(signedIn.once, 'fresh-once');
    expect(api.detailCalls, 2);
  });

  testWidgets('发送 enables after sign-in even without the cache fix', (
    tester,
  ) async {
    final api = _SessionApi();
    final container = _container(api);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const ReplyComposerPage(topicId: 1, initialText: '你好'),
        ),
      ),
    );
    // Post-frame init + draft restore + anonymous detail load.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(_sendEnabled(tester), isFalse);

    api.signedIn = true;
    await container.read(authControllerProvider.notifier).refreshAccount();
    // Sign-in rebuild, post-frame self-heal, token write, rebuild.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(_sendEnabled(tester), isTrue);
  });
}
