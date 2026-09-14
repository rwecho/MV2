import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/native/mv2_native_bridge.dart';
import 'package:mv2/core/native/widget_snapshot.dart';
import 'package:mv2/core/native/widget_sync.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/auth/data/auth_store.dart';
import 'package:mv2/features/auth/domain/auth_session.dart';
import 'package:mv2/features/notifications/application/notifications_providers.dart';
import 'package:mv2/shared/models/account_info.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/notification_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _channel = MethodChannel('mv2/native');

class _MemoryAuthStore extends AuthStore {
  _MemoryAuthStore(this.session);

  AuthSession? session;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

/// Four signed-in notifications, so `take(3)` in the snapshot is observable.
class _NotificationsApi extends FixtureV2exApi {
  _NotificationsApi() : super(latency: Duration.zero);

  /// The controller calls `refreshAccount()` after loading the page; a `null`
  /// account there signs the session out and would wipe the previews.
  @override
  Future<V2AccountInfo?> currentUser() async => const V2AccountInfo(
    user: V2User(username: 'rwecho'),
    notifications: '5',
    moneyGold: '0',
    moneySilver: '0',
    moneyBronze: '0',
  );

  @override
  Future<NotificationPage> notifications({int page = 1}) async {
    return NotificationPage(
      groups: <V2NotificationGroup>[
        V2NotificationGroup(
          title: '今天',
          items: <V2Notification>[
            for (var index = 1; index <= 4; index++)
              V2Notification(
                id: '$index',
                kind: NotificationKind.reply,
                actor: V2User(username: 'user$index'),
                timeLabel: '1 小时前',
                quote: '回复 $index',
                sourceTitle: '主题 $index',
                topicId: index,
              ),
          ],
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    calls.clear();
    mockChannel((_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('Mv2NativeBridge', () {
    test('setWidgetSnapshot sends the widget payload', () async {
      await const Mv2NativeBridge().setWidgetSnapshot(
        Mv2WidgetSnapshot(
          unreadCount: 4,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          signedIn: true,
          items: const <Mv2WidgetItem>[
            Mv2WidgetItem(actor: 'livid', text: 'hello', topicId: 7),
          ],
        ),
      );

      expect(calls.single.method, 'setWidgetSnapshot');
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['unread'], 4);
      expect(arguments['signedIn'], true);
      expect(arguments['updatedAt'], 1700000000000);
      expect((arguments['items']! as List<Object?>).single, <String, Object?>{
        'actor': 'livid',
        'text': 'hello',
        'topicId': 7,
      });
    });

    test('consumePendingQuickAction returns the buffered route', () async {
      mockChannel(
        (call) async =>
            call.method == 'consumePendingQuickAction' ? '/publish' : null,
      );

      expect(
        await const Mv2NativeBridge().consumePendingQuickAction(),
        '/publish',
      );
    });

    test('a native quickAction reaches the handler', () async {
      String? route;
      const Mv2NativeBridge().onQuickAction((String value) => route = value);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'mv2/native',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('quickAction', <String, Object?>{
                'route': '/feed/search',
              }),
            ),
            (_) {},
          );

      expect(route, '/feed/search');
    });

    test('a missing native side is a silent no-op', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);

      await const Mv2NativeBridge().setWidgetSnapshot(
        Mv2WidgetSnapshot(unreadCount: 0, updatedAt: DateTime(2026)),
      );
      expect(await const Mv2NativeBridge().consumePendingQuickAction(), isNull);
    });
  });

  test('widget sync publishes the unread count and latest previews', () async {
    final container = ProviderContainer(
      overrides: [
        authStoreProvider.overrideWithValue(
          _MemoryAuthStore(
            const AuthSession(
              user: V2User(username: 'rwecho'),
              notifications: '5',
            ),
          ),
        ),
        v2exApiProvider.overrideWithValue(_NotificationsApi()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(widgetSyncProvider, (_, _) {});
    // The real path: the notifications controller loads the page and publishes
    // the previews. Reading `notificationsProvider` directly would bypass it.
    container.listen(notificationsControllerProvider, (_, _) {});

    await container.read(notificationsProvider.future);
    // Let the controller publish, the session revalidate and the fire-and-forget
    // channel writes land.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    final snapshots = calls
        .where((call) => call.method == 'setWidgetSnapshot')
        .toList();
    expect(snapshots, isNotEmpty);

    final last = snapshots.last.arguments as Map<Object?, Object?>;
    expect(last['unread'], 5);
    expect(last['signedIn'], true);
    // Only three previews are pushed, newest first.
    final items = last['items']! as List<Object?>;
    expect(items, hasLength(3));
    expect((items.first! as Map<Object?, Object?>)['actor'], 'user1');
  });
}
