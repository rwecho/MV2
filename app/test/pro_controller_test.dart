import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/features/pro/application/pro_backend.dart';
import 'package:mv2/features/pro/application/pro_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 永久买断的权益状态机：购买/恢复/未配置各分支都要落对本地缓存与状态。
class _FakeBackend implements ProBackend {
  _FakeBackend({
    this.configured = true,
    this.purchaseOutcome = ProPurchaseOutcome.success,
    this.restoreEntitles = false,
  });

  final bool configured;
  final ProPurchaseOutcome purchaseOutcome;
  final bool restoreEntitles;

  @override
  bool get isConfigured => configured;

  @override
  Future<void> ensureReady() async {
    if (!configured) throw const ProUnconfiguredException();
  }

  @override
  Future<bool> checkEntitlement() async => false;

  @override
  Future<String> appUserId() async => 'tester';

  @override
  Future<ProProduct?> fetchLifetimeProduct() async =>
      const ProProduct(title: 'MV2 永久版', price: '¥68.00');

  @override
  Future<ProPurchaseOutcome> purchaseLifetime() async => purchaseOutcome;

  @override
  Future<bool> restore() async => restoreEntitles;
}

Future<ProviderContainer> _boot(ProBackend backend) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final controller = ProController()..debugOverrideBackend(backend);
  final container = ProviderContainer(
    overrides: [proControllerProvider.overrideWith(() => controller)],
  );
  addTearDown(container.dispose);
  await container.read(proControllerProvider.future);
  return container;
}

void main() {
  test('unconfigured build stays not-entitled and not purchasable', () async {
    final container = await _boot(_FakeBackend(configured: false));

    final state = container.read(proControllerProvider).value!;
    expect(state.configured, isFalse);
    expect(state.entitled, isFalse);
    expect(container.read(isProProvider), isFalse);
  });

  test('purchase success flips entitlement and persists it', () async {
    final container = await _boot(
      _FakeBackend(purchaseOutcome: ProPurchaseOutcome.success),
    );

    final outcome = await container
        .read(proControllerProvider.notifier)
        .purchase();

    expect(outcome, ProPurchaseOutcome.success);
    expect(container.read(isProProvider), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('mv2.pro.entitled'), isTrue);
  });

  test('cancelled purchase keeps the free state', () async {
    final container = await _boot(
      _FakeBackend(purchaseOutcome: ProPurchaseOutcome.cancelled),
    );

    final outcome = await container
        .read(proControllerProvider.notifier)
        .purchase();

    expect(outcome, ProPurchaseOutcome.cancelled);
    expect(container.read(isProProvider), isFalse);
  });

  test('pending purchase does not grant entitlement yet', () async {
    final container = await _boot(
      _FakeBackend(purchaseOutcome: ProPurchaseOutcome.pending),
    );

    final outcome = await container
        .read(proControllerProvider.notifier)
        .purchase();

    expect(outcome, ProPurchaseOutcome.pending);
    expect(container.read(isProProvider), isFalse);
  });

  test('restore picks up an existing lifetime entitlement', () async {
    final container = await _boot(_FakeBackend(restoreEntitles: true));

    final entitled = await container
        .read(proControllerProvider.notifier)
        .restore();

    expect(entitled, isTrue);
    expect(container.read(isProProvider), isTrue);
  });

  test('restore without any purchase reports no entitlement', () async {
    final container = await _boot(_FakeBackend());

    final entitled = await container
        .read(proControllerProvider.notifier)
        .restore();

    expect(entitled, isFalse);
    expect(container.read(isProProvider), isFalse);
  });

  test(
    'cold start lets the backend refresh correct the cached entitlement',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mv2.pro.entitled': true,
      });
      // 缓存说已解锁,但后端(真值)已不再报权益(退款/换绑账号):刷新后应以后端为准。
      final controller = ProController()..debugOverrideBackend(_FakeBackend());
      final container = ProviderContainer(
        overrides: [proControllerProvider.overrideWith(() => controller)],
      );
      addTearDown(container.dispose);

      await container.read(proControllerProvider.future);
      expect(container.read(isProProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('mv2.pro.entitled'), isFalse);
    },
  );
}
