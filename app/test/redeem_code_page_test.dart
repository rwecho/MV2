import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/pro/application/pro_controller.dart';
import 'package:mv2/features/pro/presentation/redeem_code_page.dart';

class _RedeemedController extends ProController {
  int restores = 0;

  @override
  Future<ProState> build() async => const ProState(configured: true);

  @override
  Future<bool> restore() async {
    restores++;
    state = const AsyncData(ProState(configured: true, entitled: true));
    return true;
  }
}

void main() {
  testWidgets('manual restore exposes sponsor wall after redemption', (
    tester,
  ) async {
    final controller = _RedeemedController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [proControllerProvider.overrideWith(() => controller)],
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const RedeemCodePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('已兑换，恢复权益'));
    await tester.pumpAndSettle();
    expect(controller.restores, 1);
    expect(find.text('前往赞助榜'), findsOneWidget);
    expect(find.text('永久版已解锁，感谢支持！'), findsOneWidget);
  });

  testWidgets(
    'returning from Play automatically restores redeemed entitlement',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (_) async => true,
      );
      final controller = _RedeemedController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [proControllerProvider.overrideWith(() => controller)],
          child: MaterialApp(
            theme: Mv2ThemeData.light(),
            home: const RedeemCodePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('前往 Google Play 兑换'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.restores, 1);
      expect(find.text('前往赞助榜'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        null,
      );
    },
  );
}
