import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/auth/domain/auth_session.dart';
import 'package:mv2/features/pro/application/pro_backend.dart';
import 'package:mv2/features/pro/application/pro_controller.dart';
import 'package:mv2/features/pro/presentation/paywall_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnavailableCommunityAccount extends AuthController {
  @override
  Future<AuthSession> build() =>
      throw StateError('Purchasing must not request a V2EX account');
}

class _Store implements ProBackend {
  int purchases = 0;
  int restores = 0;
  ProPurchaseOutcome outcome = ProPurchaseOutcome.success;

  @override
  bool get isConfigured => true;
  @override
  Future<void> ensureReady() async {}
  @override
  Future<String> appUserId() async => 'anonymous-store-customer';
  @override
  Future<bool> checkEntitlement() async => false;
  @override
  Future<ProProduct?> fetchLifetimeProduct() async =>
      const ProProduct(title: 'MV2 Pro Lifetime', price: '¥68.00');
  @override
  Future<ProPurchaseOutcome> purchaseLifetime() async {
    purchases++;
    return outcome;
  }

  @override
  Future<bool> restore() async {
    restores++;
    return true;
  }
}

Future<ProviderContainer> _pump(WidgetTester tester, _Store store) async {
  SharedPreferences.setMockInitialValues({});
  final controller = ProController()..debugOverrideBackend(store);
  final container = ProviderContainer(
    overrides: [
      proControllerProvider.overrideWith(() => controller),
      authControllerProvider.overrideWith(_UnavailableCommunityAccount.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: Mv2ThemeData.light(),
        home: const PaywallPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'guest purchases without community auth or a display-name prompt',
    (tester) async {
      final store = _Store();
      final container = await _pump(tester, store);
      await tester.ensureVisible(find.text('赞助 ¥68.00'));
      await tester.tap(find.text('赞助 ¥68.00'));
      await tester.pumpAndSettle();
      expect(store.purchases, 1);
      expect(container.read(isProProvider), isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('guest restores purchases without community auth', (
    tester,
  ) async {
    final store = _Store();
    final container = await _pump(tester, store);
    await tester.ensureVisible(find.text('恢复购买'));
    await tester.tap(find.text('恢复购买'));
    await tester.pumpAndSettle();
    expect(store.restores, 1);
    expect(container.read(isProProvider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest can retry after cancelling store payment', (tester) async {
    final store = _Store()..outcome = ProPurchaseOutcome.cancelled;
    final container = await _pump(tester, store);
    await tester.ensureVisible(find.text('赞助 ¥68.00'));
    await tester.tap(find.text('赞助 ¥68.00'));
    await tester.pumpAndSettle();
    expect(container.read(isProProvider), isFalse);
    store.outcome = ProPurchaseOutcome.success;
    await tester.tap(find.text('赞助 ¥68.00'));
    await tester.pumpAndSettle();
    expect(store.purchases, 2);
    expect(container.read(isProProvider), isTrue);
    expect(tester.takeException(), isNull);
  });
}
