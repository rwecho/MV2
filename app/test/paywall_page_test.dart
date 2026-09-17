import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/pro/application/pro_backend.dart';
import 'package:mv2/features/pro/application/pro_controller.dart';
import 'package:mv2/features/pro/presentation/paywall_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 付费墙的四种形态：已解锁 / 未配置 / 正常在售 / 拿不到商品。
class _FixedPro extends ProController {
  _FixedPro(this._state);

  final ProState _state;

  @override
  Future<ProState> build() async => _state;
}

Future<void> _pump(WidgetTester tester, ProState state) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final container = ProviderContainer(
    overrides: [proControllerProvider.overrideWith(() => _FixedPro(state))],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: Mv2ThemeData.light(),
        home: const Scaffold(body: PaywallPage()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('entitled state shows the unlocked view without a buy button', (
    tester,
  ) async {
    await _pump(tester, const ProState(configured: true, entitled: true));

    expect(find.text('已解锁永久版'), findsOneWidget);
    expect(find.textContaining('永久解锁'), findsNothing);
  });

  testWidgets('unconfigured build explains that the store is unavailable', (
    tester,
  ) async {
    await _pump(tester, const ProState(configured: false));

    expect(find.text('商店尚未配置'), findsOneWidget);
    expect(find.textContaining('永久解锁'), findsNothing);
  });

  testWidgets('ready state offers the lifetime product and restore', (
    tester,
  ) async {
    await _pump(
      tester,
      const ProState(
        configured: true,
        product: ProProduct(title: 'MV2 永久版', price: '¥68.00'),
      ),
    );

    expect(find.text('永久解锁 ¥68.00'), findsOneWidget);
    expect(find.text('恢复购买'), findsOneWidget);
  });

  testWidgets('missing product offers a retry instead of a purchase', (
    tester,
  ) async {
    await _pump(tester, const ProState(configured: true));

    expect(find.text('暂时拿不到商品信息'), findsOneWidget);
    expect(find.textContaining('永久解锁'), findsNothing);
  });
}
