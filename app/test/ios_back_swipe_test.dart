import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/app/router.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/features/topic/presentation/topic_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_container.dart';

/// Regression: the iOS edge-swipe (interactive pop) must dismiss pushed
/// full-screen routes.
///
/// go_router 18.0.0 (material_ui migration) broke its MaterialApp detection,
/// so plain `builder:` routes fell through to `NoTransitionPage` — no
/// Cupertino transition, hence no back-swipe gesture strip. `/topic/:id` and
/// `/feed/search` now carry an explicit `MaterialPage`; this test keeps them
/// honest (the sheet pages always built their own and never regressed).
void main() {
  Future<ProviderContainer> bootOnIOS(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [v2exApiProvider.overrideWithValue(fixtureApi())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const Mv2App()),
    );
    // Fixture providers resolve after ~250ms and the skeleton shimmer runs
    // indefinitely, so pumps — never pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  /// The Cupertino back gesture: press inside the 20px edge strip, drag past
  /// half the screen width across a few frames, release.
  Future<void> edgeSwipeBack(WidgetTester tester) async {
    final gesture = await tester.startGesture(const Offset(2, 400));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(35, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    // Pop transition plus margin; explicit pumps because the shimmer never
    // settles.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    // The invariant check runs before tearDowns; reset inside the body.
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('iOS edge swipe pops the pushed /topic/:id route', (
    tester,
  ) async {
    final container = await bootOnIOS(tester);

    unawaited(container.read(routerProvider).push('/topic/1'));
    // Entrance transition is 500ms and the first pump after push starts the
    // ticker, so three pumps are needed before the swipe can arm.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TopicDetailPage), findsOneWidget);

    await edgeSwipeBack(tester);

    expect(
      find.byType(TopicDetailPage),
      findsNothing,
      reason: 'the topic route should have been popped by the edge swipe',
    );
  });

  testWidgets('iOS edge swipe pops the /feed/search route', (tester) async {
    final container = await bootOnIOS(tester);

    unawaited(container.read(routerProvider).push('/feed/search'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await edgeSwipeBack(tester);

    expect(
      container.read(routerProvider).routerDelegate.currentConfiguration.uri,
      isNot(contains('/search')),
      reason: 'the search route should have been popped by the edge swipe',
    );
  });

  testWidgets('iOS edge swipe pops the /settings route', (tester) async {
    final container = await bootOnIOS(tester);

    unawaited(container.read(routerProvider).push('/settings'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await edgeSwipeBack(tester);

    expect(
      container.read(routerProvider).routerDelegate.currentConfiguration.uri,
      isNot(contains('/settings')),
      reason: 'the settings route should have been popped by the edge swipe',
    );
  });
}
