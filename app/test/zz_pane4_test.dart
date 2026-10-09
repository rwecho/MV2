import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/features/topic/presentation/topic_detail_page.dart';
import 'package:mv2/ui/components/topic_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_container.dart';

void main() {
  testWidgets('dbg pane4', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [v2exApiProvider.overrideWithValue(fixtureApi())]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const Mv2App()));
    for (var i = 0; i < 3; i++) { await tester.pump(const Duration(milliseconds: 400)); }
    await tester.tap(find.byType(TopicItem).first);
    for (var i = 0; i < 8; i++) { await tester.pump(const Duration(milliseconds: 400)); }
    final icons = tester.widgetList<Icon>(find.descendant(of: find.byType(TopicDetailPage), matching: find.byType(Icon))).map((i) => i.icon).toSet();
    debugPrint('DBG icons=$icons');
    debugPrint('DBG inPane=${tester.widget<TopicDetailPage>(find.byType(TopicDetailPage)).inPane}');
    debugPrint('DBG hasBackIcon=${find.byIcon(Icons.arrow_back_ios_new_rounded).evaluate().length}');
  });
}
