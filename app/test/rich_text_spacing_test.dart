import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_rich_text.dart';

/// Regression tests for the "some topics have huge line spacing" bug.
///
/// V2EX serves two shapes of `div.topic_content`:
///
/// * plain topics — flat text with `<br />` separators;
/// * Markdown topics — `div.markdown_body > p…` (`/t/1241327`, `/t/1241226`).
///
/// The nested shape used to render every inline fragment (and every whitespace
/// node between `</p> <p>`) as its own 12px-spaced block, so Markdown topics
/// looked double- or triple-spaced while plain ones were fine.
Future<void> pumpBody(WidgetTester tester, String html) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: Mv2ThemeData.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 300, child: Mv2RichText(html: html)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder bodyTexts() =>
    find.descendant(of: find.byType(Mv2RichText), matching: find.byType(Text));

/// Bottom of the lowest rendered text — a stand-in for content height, since
/// the root `Column` stretches to the viewport.
double bodyHeight(WidgetTester tester) {
  var bottom = 0.0;
  for (final element in bodyTexts().evaluate()) {
    final rect = tester.getRect(find.byWidget(element.widget));
    if (rect.bottom > bottom) bottom = rect.bottom;
  }
  return bottom;
}

void main() {
  testWidgets('inline fragments inside a <p> stay on one flowing line', (
    tester,
  ) async {
    await pumpBody(
      tester,
      '<p>第二段 <a href="https://x.com">https://x.com</a> 后面还有文字。</p>',
    );
    expect(bodyTexts(), findsOneWidget);
  });

  testWidgets('a Markdown paragraph nests a link without splitting it', (
    tester,
  ) async {
    await pumpBody(
      tester,
      '<div class="markdown_body"><p>第一段 <strong>加粗</strong> 结尾</p>'
      '<p>第二段 <a href="https://x.com">链接</a> 结尾</p></div>',
    );
    expect(bodyTexts(), findsNWidgets(2));
  });

  testWidgets('whitespace between </p> <p> does not become a blank block', (
    tester,
  ) async {
    await pumpBody(
      tester,
      '<div class="markdown_body"><p>甲</p>\n<p>乙</p>\n<p>丙</p></div>',
    );
    expect(bodyTexts(), findsNWidgets(3));
  });

  testWidgets('flat <br /> body still flows into one text', (tester) async {
    await pumpBody(tester, '第一段<br /><br />第二段');
    expect(bodyTexts(), findsOneWidget);
    expect(
      tester.widget<Text>(bodyTexts()).textSpan!.toPlainText(),
      '第一段\n\n第二段',
    );
  });

  testWidgets('Markdown and plain bodies with equal content space similarly', (
    tester,
  ) async {
    const paragraphs = <String>['第一段内容。', '第二段内容。', '第三段内容。'];

    await pumpBody(tester, paragraphs.map((p) => '<p>$p</p>').join());
    final nested = bodyHeight(tester);
    expect(bodyTexts(), findsNWidgets(paragraphs.length));

    await pumpBody(tester, paragraphs.join('<br /><br />'));
    final flat = bodyHeight(tester);

    // Before the fix the nested shape ran ~2.5× the flat height.
    expect(nested, lessThan(flat * 1.3));
  });
}
