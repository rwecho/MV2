import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/design_system/tokens/mv2_typography.dart';
import 'package:mv2/ui/components/mv2_tab_strip.dart';
import 'package:mv2/core/data/home_tab.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/features/feed/application/feed_providers.dart';
import 'package:mv2/features/shell/application/shell_chrome.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/ui/components/xna_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fixture_api.dart';
import 'support/test_container.dart';

/// Counts `feed()` calls so a pull-to-refresh can be observed.
class _CountingApi extends FixtureV2exApi {
  _CountingApi() : super(latency: Duration.zero);

  int feedCalls = 0;

  @override
  Future<List<V2Topic>> feed(
    HomeTab tab, {
    PacePriority priority = PacePriority.userRead,
  }) {
    feedCalls++;
    return super.feed(tab);
  }
}

/// Fails every feed load so the first-load toast can be observed.
///
/// A *non-retryable* [Failure]: the feed provider's `mv2Retry` policy lets it
/// reach the error state at once. A retryable failure (e.g. [NetworkFailure])
/// would stay in Riverpod's retry `AsyncLoading` for the whole backoff, which
/// is the behaviour `home_feed_page.dart` deliberately relies on.
class _FailingApi extends FixtureV2exApi {
  _FailingApi() : super(latency: Duration.zero);

  @override
  Future<List<V2Topic>> feed(
    HomeTab tab, {
    PacePriority priority = PacePriority.userRead,
  }) async {
    throw const ParseFailure('feed fixture');
  }
}

/// The home content is a `PageView`, so a horizontal swipe must move between
/// tabs and stay in sync with the top strip (both directions).
void main() {
  Future<ProviderContainer> boot(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer(
      overrides: [v2exApiProvider.overrideWithValue(fixtureApi())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const Mv2App()),
    );
    await tester.pump();
    // Fixture providers resolve after ~250ms; the list also runs a skeleton
    // shimmer, so never use pumpAndSettle here.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  testWidgets('swiping the content moves to the next tab', (tester) async {
    final container = await boot(tester);
    expect(container.read(homeTabProvider), HomeTab.r2);
    expect(find.byType(PageView), findsOneWidget);

    // R2 is the last topic tab; swipe left to reach VXNA.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(homeTabProvider), HomeTab.vxna);
    expect(find.byType(XnaItem), findsWidgets);

    // …and swiping right goes back to R2.
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(homeTabProvider), HomeTab.r2);
  });

  testWidgets('the swipe selection is persisted', (tester) async {
    final container = await boot(tester);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(HomeTabController.storageKey), 'vxna');
    expect(container.read(homeTabProvider), HomeTab.vxna);
  });

  testWidgets('reading down flips the shared collapse state', (
    tester,
  ) async {
    // Shrink the viewport so the short fixture list is scrollable.
    tester.view.physicalSize = const Size(400, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const titleKey = ValueKey<String>('mv2-feed-bar-title');
    double titleFontSize() => tester
        .widget<AnimatedDefaultTextStyle>(find.byKey(titleKey))
        .style
        .fontSize!;

    final container = await boot(tester);
    expect(container.read(shellBarCollapsedProvider), isFalse);
    expect(find.byType(Mv2TabStrip), findsOneWidget);
    expect(titleFontSize(), Mv2Typography.standard().sectionTitle.fontSize);

    // Scroll toward the end of the list — the title collapses to the bar size
    // (it never hides) and the shared collapse state flips.
    await tester.drag(find.byType(PageView), const Offset(0, -160));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(shellBarCollapsedProvider), isTrue);
    expect(
      titleFontSize(),
      Mv2Typography.standard().itemTitle.fontSize,
      reason: 'reading down collapses the title',
    );
    // 头部收缩:标签条收起,把垂直空间让给列表。
    expect(find.byType(Mv2TabStrip), findsNothing);

    // Scroll back — the title expands again.
    await tester.drag(find.byType(PageView), const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(shellBarCollapsedProvider), isFalse);
    expect(titleFontSize(), Mv2Typography.standard().sectionTitle.fontSize);
  });

  testWidgets('pulling down refreshes the active tab', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final api = _CountingApi();
    final container = ProviderContainer(
      overrides: [v2exApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const Mv2App()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    final before = api.feedCalls;
    expect(before, greaterThanOrEqualTo(1));

    // Pull the list down from the top to trigger the refresh indicator.
    await tester.fling(find.byType(PageView), const Offset(0, 350), 1000);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(api.feedCalls, greaterThan(before));
  });

  testWidgets('a failed tab load shows a toast and the error state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer(
      overrides: [v2exApiProvider.overrideWithValue(_FailingApi())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const Mv2App()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('数据解析失败，页面结构可能已变更。'), findsOneWidget);
    expect(find.text('加载失败'), findsOneWidget);
  });
}
