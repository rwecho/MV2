import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/app/router.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/features/settings/application/settings_controller.dart';
import 'package:mv2/features/settings/presentation/settings_page.dart';
import 'package:mv2/features/shell/application/tablet_topic_pane.dart';
import 'package:mv2/features/shell/presentation/app_shell.dart';
import 'package:mv2/features/topic/application/open_topic.dart';
import 'package:mv2/features/topic/presentation/topic_detail_page.dart';
import 'package:mv2/ui/components/mv2_floating_tab_bar.dart';
import 'package:mv2/ui/components/topic_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_container.dart';

/// The tablet two-pane layout: on wide viewports tapping a topic opens it in
/// the right-hand detail pane (no route push), while phones keep pushing the
/// full-screen `/topic/:id` route.
void main() {
  Future<ProviderContainer> boot(WidgetTester tester, Size size) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = size;
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

  testWidgets('tablet: tapping a topic fills the detail pane, back empties it', (
    tester,
  ) async {
    final container = await boot(tester, const Size(1200, 900));

    // Two-pane starts with the empty right pane.
    expect(find.text('未选择主题'), findsOneWidget);
    expect(container.read(tabletTopicPaneProvider), isNull);

    await tester.tap(find.byType(TopicItem).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // The selection went to the pane — no route was pushed — and the empty
    // state made way for the topic.
    final selection = container.read(tabletTopicPaneProvider);
    expect(selection, isNotNull);
    expect(find.text('未选择主题'), findsNothing);
    expect(find.byType(TopicDetailPage), findsOneWidget);

    // The pane's back affordance closes it instead of popping a route.
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(tabletTopicPaneProvider), isNull);
    expect(find.text('未选择主题'), findsOneWidget);
  });

  testWidgets('phone: tapping a topic still pushes the full-screen route', (
    tester,
  ) async {
    final container = await boot(tester, const Size(390, 844));

    await tester.tap(find.byType(TopicItem).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // No pane involvement below the breakpoint; the only TopicDetailPage in
    // the tree must come from the pushed route.
    expect(container.read(tabletTopicPaneProvider), isNull);
    expect(find.byType(TopicDetailPage), findsOneWidget);
  });

  testWidgets('tablet: secondary pages present as a floating card', (
    tester,
  ) async {
    final container = await boot(tester, const Size(1200, 900));

    unawaited(container.read(routerProvider).push('/settings'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final route = ModalRoute.of(tester.element(find.byType(SettingsPage)));
    expect(route, isNotNull);
    // The card paints its own backdrop, so the route is self-contained.
    expect(route!.opaque, isTrue);
    expect(route.settings.name, '/settings');
    // The shell below keeps its state mounted (offstage while covered).
    expect(
      find.byType(Mv2FloatingTabBar, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('phone: secondary pages stay the full-screen push', (
    tester,
  ) async {
    final container = await boot(tester, const Size(390, 844));

    // No two-pane chrome below the breakpoint.
    expect(find.byKey(const Key('pane_divider')), findsNothing);

    unawaited(container.read(routerProvider).push('/settings'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final route = ModalRoute.of(tester.element(find.byType(SettingsPage)));
    expect(route, isNotNull);
    expect(route!.opaque, isTrue);
  });

  testWidgets('tablet: dragging the divider resizes and clamps the panes', (
    tester,
  ) async {
    final container = await boot(tester, const Size(1200, 900));
    final divider = find.byKey(const Key('pane_divider'));
    expect(divider, findsOneWidget);
    expect(
      container.read(settingsProvider).splitRatio,
      closeTo(defaultSplitRatio, 0.0001),
    );

    // Drag right: the left pane grows. (Exact deltas depend on the gesture
    // recognizer's touch slop, so assert direction, not arithmetic.)
    await tester.drag(divider, const Offset(120, 0));
    await tester.pump();
    expect(
      container.read(settingsProvider).splitRatio,
      greaterThan(defaultSplitRatio),
    );

    // Drag far past the clamp: the detail pane keeps its minimum, and the
    // stored ratio saturates at the settings bound.
    await tester.drag(divider, const Offset(2000, 0));
    await tester.pump();
    expect(container.read(settingsProvider).splitRatio, maxSplitRatio);

    // …and far the other way: the divider's own width floor (320pt) bites
    // before the settings ratio floor at this window width.
    await tester.drag(divider, const Offset(-4000, 0));
    await tester.pump();
    expect(
      container.read(settingsProvider).splitRatio,
      closeTo(minPaneWidth / 1200, 0.001),
    );

    // The choice persists.
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getDouble('mv2.splitRatio'),
      closeTo(minPaneWidth / 1200, 0.001),
    );
  });

  testWidgets('tablet: opening a topic from a card closes the card', (
    tester,
  ) async {
    final container = await boot(tester, const Size(1200, 900));

    unawaited(container.read(routerProvider).push('/settings'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SettingsPage), findsOneWidget);

    // Simulates a topic tap from inside the card (member page, my topics, …).
    openTopic(tester.element(find.byType(SettingsPage)), 42);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // The pane took the topic and the card is gone, revealing the two-pane.
    expect(container.read(tabletTopicPaneProvider)?.topicId, 42);
    expect(find.byType(SettingsPage), findsNothing);
  });
}
