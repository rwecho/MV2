import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_collapsible_body.dart';

void main() {
  Future<void> pump(WidgetTester tester, {double height = 400}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: Mv2CollapsibleBody(
              child: SizedBox(height: height, width: 320),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('starts collapsed with an 展开全文 affordance', (tester) async {
    await pump(tester);

    expect(find.text('展开全文'), findsOneWidget);
    expect(find.text('收起'), findsNothing);
    // The body is clipped to the collapsed height, not removed.
    expect(tester.getSize(find.byType(Mv2CollapsibleBody)).height, lessThan(400));
  });

  testWidgets('tapping 展开全文 reveals the whole body', (tester) async {
    await pump(tester);
    final collapsed = tester.getSize(find.byType(Mv2CollapsibleBody)).height;

    await tester.tap(find.text('展开全文'));
    await tester.pump();

    expect(find.text('收起'), findsOneWidget);
    expect(
      tester.getSize(find.byType(Mv2CollapsibleBody)).height,
      greaterThan(collapsed),
    );
  });

  testWidgets('tapping 收起 clamps it again', (tester) async {
    await pump(tester);
    await tester.tap(find.text('展开全文'));
    await tester.pump();
    final expanded = tester.getSize(find.byType(Mv2CollapsibleBody)).height;

    await tester.tap(find.text('收起'));
    await tester.pump();

    expect(find.text('展开全文'), findsOneWidget);
    expect(
      tester.getSize(find.byType(Mv2CollapsibleBody)).height,
      lessThan(expanded),
    );
  });
}
