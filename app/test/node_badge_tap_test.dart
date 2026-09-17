import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/features/nodes/presentation/node_topic_page.dart';
import 'package:mv2/features/topic/presentation/topic_detail_page.dart';
import 'package:mv2/ui/components/topic_item.dart';
import 'package:mv2/ui/primitives/mv2_chips.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_container.dart';

/// The node badge is its own tap target: tapping it opens the node's topic
/// stream (`/node/:key`), while tapping anywhere else on the card still opens
/// the topic.
void main() {
  Future<ProviderContainer> bootPhone(WidgetTester tester) async {
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
    // Fixture providers resolve after ~250ms and the skeleton shimmer never
    // stops, so pump fixed durations — never `pumpAndSettle`.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  Future<void> settleRoute(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('tapping a node badge in the topic list opens the node page', (
    tester,
  ) async {
    await bootPhone(tester);

    final badge = find.descendant(
      of: find.byType(TopicItem).first,
      matching: find.byType(Mv2NodeBadge),
    );
    expect(badge, findsOneWidget);

    await tester.tap(badge);
    await settleRoute(tester);

    expect(find.byType(NodeTopicPage), findsOneWidget);
    // The node page, not the topic the card itself points at.
    expect(find.byType(TopicDetailPage), findsNothing);
    // Slug in the path, display name in `?name=` (the fixture's first card is
    // `programmer` / `程序员`).
    final page = tester.widget<NodeTopicPage>(find.byType(NodeTopicPage));
    expect(page.nodeName, 'programmer');
    expect(page.displayName, '程序员');
  });

  testWidgets('the rest of the card still opens the topic', (tester) async {
    await bootPhone(tester);

    // The title sits next to the badge but outside its own tap target.
    await tester.tap(find.byType(TopicItem).first);
    await settleRoute(tester);

    expect(find.byType(TopicDetailPage), findsOneWidget);
    expect(find.byType(NodeTopicPage), findsNothing);
  });

  testWidgets('tapping the node badge on the topic page opens the node page', (
    tester,
  ) async {
    await bootPhone(tester);

    await tester.tap(find.byType(TopicItem).first);
    await settleRoute(tester);
    expect(find.byType(TopicDetailPage), findsOneWidget);

    final badge = find.descendant(
      of: find.byType(TopicDetailPage),
      matching: find.byType(Mv2NodeBadge),
    );
    expect(badge, findsOneWidget);

    await tester.tap(badge);
    await settleRoute(tester);

    expect(find.byType(NodeTopicPage), findsOneWidget);
  });
}
