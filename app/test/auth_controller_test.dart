import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/home_tab.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/shared/models/login_form.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/auth/data/auth_store.dart';
import 'package:mv2/features/auth/domain/auth_session.dart';
import 'package:mv2/shared/models/account_info.dart';
import 'package:mv2/shared/models/daily_mission.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/notification_page.dart';
import 'package:mv2/shared/models/publish_form.dart';
import 'package:mv2/shared/models/topic_detail.dart';
import 'package:mv2/shared/models/write_result.dart';

/// In-memory `AuthStore` so the controller can be exercised without the
/// keychain (`FlutterSecureStorage` has no test implementation).
class _MemoryAuthStore extends AuthStore {
  _MemoryAuthStore([this.session]);

  AuthSession? session;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

/// Minimal `V2exApi` stub: only the account endpoints are meaningful, every
/// other method fails loudly if a test reaches it.
class _FakeApi implements V2exApi {
  V2AccountInfo? account;
  Object? error;

  @override
  Future<V2LoginForm?> loginForm() async => null;

  @override
  Future<List<int>> captchaImage(String captchaPath, {String? once}) async =>
      const <int>[];

  @override
  Future<V2LoginResult> login({
    required V2LoginForm form,
    required String username,
    required String password,
    required String captcha,
  }) async => const V2LoginResult(success: false);

  @override
  Future<V2LoginResult> twoStep({
    required V2LoginForm form,
    required String code,
  }) async => const V2LoginResult(success: false);

  @override
  Future<V2AccountInfo?> currentUser() async {
    final failure = error;
    if (failure != null) throw failure;
    return account;
  }

  @override
  Future<V2DailyMission> dailyMission() async => const V2DailyMission();

  @override
  Future<V2DailyMission> checkIn() async => const V2DailyMission();

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
  Future<V2TopicForm> topicForm({String? node}) => throw UnimplementedError();

  @override
  Future<V2PublishResult> publishTopic({
    required V2TopicForm form,
    required String nodeName,
    required String title,
    required String content,
  }) => throw UnimplementedError();

  @override
  Future<V2WriteResult> replyToTopic(
    int topicId,
    String content,
    String once,
  ) => throw UnimplementedError();

  @override
  Future<V2WriteResult> thankTopic(int topicId, String once) =>
      throw UnimplementedError();

  @override
  Future<V2WriteResult> thankReply(String replyId, String once) =>
      throw UnimplementedError();

  @override
  Future<V2WriteResult> favoriteTopic(int topicId, String once) =>
      throw UnimplementedError();

  @override
  Future<V2WriteResult> unfavoriteTopic(int topicId, String once) =>
      throw UnimplementedError();

  @override
  Future<V2WriteResult> ignoreTopic(int topicId, String once) =>
      throw UnimplementedError();

  @override
  Future<V2WriteResult> unignoreTopic(int topicId, String once) =>
      throw UnimplementedError();

  @override
  Future<V2WriteResult> ignoreReply(String replyId, String once) =>
      throw UnimplementedError();

  @override
  Future<V2WriteResult> appendTopic(int topicId, String content, String once) =>
      throw UnimplementedError();

  @override
  Future<V2WriteResult> ignoreNode(String nodeId, String once) =>
      throw UnimplementedError();
}

V2AccountInfo _accountInfo() => const V2AccountInfo(
  user: V2User(
    username: 'rwecho',
    id: 94728,
    avatarUrl: 'https://cdn.v2ex.com/avatar/a1b2/c3d4/94728_large.png',
  ),
  notifications: '3',
  moneyGold: '9.6',
  moneySilver: '120',
  moneyBronze: '0',
);

AuthSession _storedSession() => const AuthSession(
  user: V2User(username: 'rwecho', id: 94728),
  signedInAt: null,
);

ProviderContainer _container({
  required _MemoryAuthStore store,
  required _FakeApi api,
}) {
  return ProviderContainer.test(
    overrides: [
      authStoreProvider.overrideWithValue(store),
      v2exApiProvider.overrideWithValue(api),
      // An in-memory jar keeps `signOut`/`seedCookie` off the keychain.
      httpClientProvider.overrideWithValue(Mv2HttpClient(Dio(), CookieJar())),
    ],
  );
}

void main() {
  group('AuthSession storage', () {
    test('round-trips user, member id, avatar and timestamp', () {
      final session = AuthSession(
        user: const V2User(
          username: 'rwecho',
          id: 94728,
          avatarUrl: 'https://cdn.v2ex.com/avatar/a1b2/c3d4/94728_large.png',
        ),
        signedInAt: DateTime.parse('2026-09-11T08:00:00.000Z'),
      );

      final restored = AuthSession.fromStorage(session.toStorage());

      expect(restored, isNotNull);
      expect(restored!.username, 'rwecho');
      expect(restored.memberId, 94728);
      expect(
        restored.user!.avatarUrl,
        'https://cdn.v2ex.com/avatar/a1b2/c3d4/94728_large.png',
      );
      expect(restored.signedInAt, DateTime.parse('2026-09-11T08:00:00.000Z'));
      expect(restored.isSignedIn, isTrue);
    });

    test('an empty or username-less map restores to null', () {
      expect(AuthSession.fromStorage(const <String, String?>{}), isNull);
      expect(
        AuthSession.fromStorage(const <String, String?>{'username': ''}),
        isNull,
      );
    });
  });

  group('AuthController', () {
    test('starts signed out when storage is empty', () async {
      final container = _container(store: _MemoryAuthStore(), api: _FakeApi());

      final session = await container.read(authControllerProvider.future);

      expect(session.isSignedIn, isFalse);
      expect(container.read(isSignedInProvider), isFalse);
      expect(container.read(currentUsernameProvider), isNull);
    });

    test('signInWithCookies seeds cookies, validates and persists', () async {
      final store = _MemoryAuthStore();
      final api = _FakeApi()..account = _accountInfo();
      final container = _container(store: store, api: api);

      await container.read(authControllerProvider.future);
      await container.read(authControllerProvider.notifier).signInWithCookies(
        <Cookie>[Cookie('A2', 'session-token')],
      );

      final session = container.read(authControllerProvider).value!;
      expect(session.isSignedIn, isTrue);
      expect(session.username, 'rwecho');
      expect(session.memberId, 94728);
      expect(session.notifications, '3');
      expect(container.read(currentUsernameProvider), 'rwecho');
      expect(store.session?.username, 'rwecho');
    });

    test('currentUser() == null signs out as sessionExpired', () async {
      final store = _MemoryAuthStore(_storedSession());
      final api = _FakeApi()..account = null;
      final container = _container(store: store, api: api);

      await container.read(authControllerProvider.future);
      expect(container.read(isSignedInProvider), isTrue);

      await container.read(authControllerProvider.notifier).refreshAccount();

      expect(container.read(isSignedInProvider), isFalse);
      expect(store.session, isNull);
      expect(
        container.read(authControllerProvider.notifier).lastSignOutReason,
        SignOutReason.sessionExpired,
      );
    });

    test('signOut() clears the persisted session (user initiated)', () async {
      final store = _MemoryAuthStore(_storedSession());
      final api = _FakeApi()..account = _accountInfo();
      final container = _container(store: store, api: api);

      await container.read(authControllerProvider.future);
      final controller = container.read(authControllerProvider.notifier);

      await controller.signOut();

      expect(container.read(isSignedInProvider), isFalse);
      expect(store.session, isNull);
      expect(controller.lastSignOutReason, SignOutReason.userInitiated);
    });

    test('a transient network error keeps an existing session', () async {
      final store = _MemoryAuthStore(_storedSession());
      final api = _FakeApi()..error = const NetworkFailure();
      final container = _container(store: store, api: api);

      await container.read(authControllerProvider.future);
      expect(container.read(isSignedInProvider), isTrue);

      await container.read(authControllerProvider.notifier).refreshAccount();

      final state = container.read(authControllerProvider);
      expect(state.hasError, isFalse);
      expect(state.value!.isSignedIn, isTrue);
      expect(store.session, isNotNull);
      expect(
        container.read(authControllerProvider.notifier).lastSignOutReason,
        isNull,
      );
    });
  });
}
