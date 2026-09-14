import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_rich_text.dart';

/// Structural checks for the Markdown block renderer (lists, quotes, images,
/// headings). Typography itself is asserted through the resolved `TextStyle`.
Future<void> pump(WidgetTester tester, String html) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: Mv2ThemeData.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 320, child: Mv2RichText(html: html)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('unordered lists use level-specific bullets and nest', (
    tester,
  ) async {
    await pump(tester, '<ul><li>甲</li><li>乙<ul><li>乙一</li></ul></li></ul>');

    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('◦'), findsOneWidget);
    expect(find.textContaining('乙一'), findsOneWidget);
  });

  testWidgets('ordered lists number items and honour start', (tester) async {
    await pump(tester, '<ol start="3"><li>甲</li><li>乙</li></ol>');

    expect(find.text('3.'), findsOneWidget);
    expect(find.text('4.'), findsOneWidget);
  });

  testWidgets('a linked image renders instead of being dropped', (
    tester,
  ) async {
    await pump(
      tester,
      '<p><a href="https://www.v2ex.com/t/1">'
      '<img src="https://cdn.v2ex.com/avatar/x.png"></a></p>',
    );

    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('blockquote keeps its paragraph breaks', (tester) async {
    await pump(tester, '<blockquote><p>引用第一段</p><p>引用第二段</p></blockquote>');

    expect(find.textContaining('引用第一段'), findsOneWidget);
    expect(find.textContaining('引用第二段'), findsOneWidget);
  });

  testWidgets('headings step down in size', (tester) async {
    await pump(tester, '<h1>大标题</h1><h3>小标题</h3>');

    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    final h1 = texts.firstWhere((t) => t.textSpan?.toPlainText() == '大标题');
    final h3 = texts.firstWhere((t) => t.textSpan?.toPlainText() == '小标题');
    expect(h1.style!.fontSize!, greaterThan(h3.style!.fontSize!));
  });
}
