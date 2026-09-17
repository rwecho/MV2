import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/pro/application/honors_controller.dart';
import 'package:mv2/features/pro/application/pro_controller.dart';
import 'package:mv2/features/pro/data/honors_api.dart';
import 'package:mv2/features/pro/presentation/honor_wall_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 荣誉墙页面的三种形态：有名单 / 空墙 + 未购买 / 已购买未登记。
class _FixedHonors extends HonorsController {
  _FixedHonors(this._state);

  final HonorsState _state;

  @override
  Future<HonorsState> build() async => _state;
}

class _FixedPro extends ProController {
  _FixedPro(this._entitled);

  final bool _entitled;

  @override
  Future<ProState> build() async =>
      ProState(configured: true, entitled: _entitled);
}

Future<void> _pump(
  WidgetTester tester, {
  required HonorsState honors,
  required bool isPro,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: HonorWallPage(source: 'test')),
      ),
      GoRoute(
        path: '/pro',
        builder: (_, _) => const Scaffold(body: Text('paywall')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [
      honorsControllerProvider.overrideWith(() => _FixedHonors(honors)),
      proControllerProvider.overrideWith(() => _FixedPro(isPro)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: Mv2ThemeData.light(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('engraved names render with rank, name and date', (tester) async {
    await _pump(
      tester,
      isPro: true,
      honors: HonorsState(
        entries: <HonorEntry>[
          HonorEntry(name: 'livid', joinedAt: DateTime(2026, 1, 2)),
          HonorEntry(name: 'another', joinedAt: DateTime(2026, 2, 15)),
        ],
        joined: true,
      ),
    );

    expect(find.text('livid'), findsOneWidget);
    expect(find.text('another'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('2026.01.02'), findsOneWidget);
    expect(find.text('你的名字已在这面墙上'), findsOneWidget);
  });

  testWidgets('an empty wall invites the first buyer and unlocks', (
    tester,
  ) async {
    await _pump(tester, isPro: false, honors: const HonorsState());

    expect(find.text('荣誉墙还空着'), findsOneWidget);
    expect(find.text('去解锁永久版'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a purchaser who has not engraved sees the join affordance', (
    tester,
  ) async {
    await _pump(tester, isPro: true, honors: const HonorsState());

    expect(find.text('把我的名字刻上荣誉墙'), findsOneWidget);
  });
}
