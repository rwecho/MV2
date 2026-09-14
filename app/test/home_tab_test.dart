import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/home_tab.dart';
import 'package:mv2/features/feed/application/feed_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeTab', () {
    test('mirrors the V2EX #Tabs order and labels', () {
      expect(HomeTab.values.map((tab) => tab.label).toList(), <String>[
        '技术',
        '创意',
        '好玩',
        'Apple',
        '酷工作',
        '交易',
        '城市',
        '问与答',
        '最热',
        '全部',
        'R2',
        'VXNA',
      ]);
    });

    test('maps each tab to its site path', () {
      expect(HomeTab.tech.path, '/?tab=tech');
      expect(HomeTab.hot.path, '/?tab=hot');
      expect(HomeTab.r2.path, '/?tab=r2');
      // VXNA is not a `?tab=` topic list — it lives at its own path.
      expect(HomeTab.vxna.path, '/xna');
      expect(HomeTab.vxna.isAggregator, isTrue);
      expect(HomeTab.all.isAggregator, isFalse);
    });

    test('fromName round-trips and rejects unknown values', () {
      for (final tab in HomeTab.values) {
        expect(HomeTab.fromName(tab.name), tab);
      }
      expect(HomeTab.fromName('nope'), isNull);
      expect(HomeTab.fromName(null), isNull);
    });

    test('first run defaults to R2', () {
      expect(HomeTab.initial, HomeTab.r2);
    });
  });

  group('HomeTabController', () {
    test('defaults to R2 then persists the selection', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(homeTabProvider), HomeTab.r2);

      await container.read(homeTabProvider.notifier).select(HomeTab.qna);
      expect(container.read(homeTabProvider), HomeTab.qna);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(HomeTabController.storageKey), 'qna');
    });

    test('restores the persisted tab on startup', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        HomeTabController.storageKey: 'creative',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // The first frame renders the default, then storage hydrates.
      expect(container.read(homeTabProvider), HomeTab.r2);
      for (var i = 0; i < 20; i++) {
        if (container.read(homeTabProvider) == HomeTab.creative) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(container.read(homeTabProvider), HomeTab.creative);
    });
  });
}
