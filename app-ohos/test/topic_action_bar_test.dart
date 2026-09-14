import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/topic_action_bar.dart';

/// The topic `感谢` action must reflect [TopicActionBar.thanked]; it previously
/// ignored the flag, so a successful thank changed nothing on screen.
Future<void> pump(WidgetTester tester, {required bool thanked}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: Mv2ThemeData.light(),
      home: Scaffold(body: TopicActionBar(thanked: thanked)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a thanked topic shows a filled 已感谢 action', (tester) async {
    await pump(tester, thanked: true);

    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.text('已感谢'), findsOneWidget);
  });

  testWidgets('an unthanked topic shows the outline 感谢 action', (tester) async {
    await pump(tester, thanked: false);

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    expect(find.text('感谢'), findsOneWidget);
  });
}
