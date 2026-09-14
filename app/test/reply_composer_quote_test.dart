import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/composer/presentation/reply_composer_page.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The composer's quote block must mirror the reply the user tapped 引用 on
/// instead of rendering a fixed fixture.
void main() {
  Future<void> pumpComposer(
    WidgetTester tester,
    ProviderContainer container,
    ReplyComposerPage page,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: Mv2ThemeData.light(), home: page),
      ),
    );
  }

  testWidgets('quoted reply is rendered instead of the fixed mock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const reply = V2Reply(
      floor: 2,
      author: V2User(username: 'sentinelK'),
      content: '@sentinelK 没有列全部的具体数据，但列了一些例子以及他们蒸馏的方法。',
      createdAtLabel: '1 小时前',
    );

    await pumpComposer(
      tester,
      container,
      const ReplyComposerPage(topicId: 1, floor: 2, quotedReply: reply),
    );
    await tester.pump();
    // Drain the fixture latency so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('回复 @sentinelK'), findsOneWidget);
    expect(find.textContaining('没有列全部的具体数据'), findsOneWidget);
    // The old hard-coded fixture must be gone.
    expect(find.text('回复 @kernel'), findsNothing);
  });

  testWidgets('floor-only deep link resolves the quote from the topic detail', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpComposer(
      tester,
      container,
      const ReplyComposerPage(topicId: 1, floor: 1),
    );
    await tester.pump();
    // Fixture latency + detail load.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Floor 1 of the bundled topic fixture is authored by sentinelK.
    expect(find.text('回复 @sentinelK'), findsOneWidget);
    expect(find.text('回复 @kernel'), findsNothing);
  });

  testWidgets('initialText seeds an empty editor with the floor marker', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpComposer(
      tester,
      container,
      const ReplyComposerPage(topicId: 1, floor: 5, initialText: '#5 '),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '#5 ');
  });

  testWidgets('a restored draft wins over the floor marker', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mv2.draft.topic.1': '我之前的草稿',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpComposer(
      tester,
      container,
      const ReplyComposerPage(topicId: 1, floor: 5, initialText: '#5 '),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '我之前的草稿');
  });
}
