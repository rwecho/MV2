import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_rich_text.dart';

/// Regression tests for the "every emoticon breaks onto its own line" bug.
///
/// V2EX serves 表情 as small inline images — the topic-title heart is
/// `<img src="/static/img/heart….png" width="14" align="absmiddle" alt="❤️">`,
/// and V2EX Polish's 流行 set expands to hosted image URLs. `Mv2RichText`
/// treated every `img` as a block picture, so each emoticon stranded the
/// surrounding text on separate lines.
Future<void> pumpBody(
  WidgetTester tester,
  String html, {
  bool settle = true,
}) async {
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
  // Network images never resolve under the test binding, so the WidgetSpan
  // cases settle into their placeholder without pumpAndSettle.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder bodyTexts() =>
    find.descendant(of: find.byType(Mv2RichText), matching: find.byType(Text));

String plainText(WidgetTester tester) =>
    tester.widget<Text>(bodyTexts().first).textSpan!.toPlainText();

dom.Element img(String html) =>
    html_parser.parseFragment(html).children.single as dom.Element;

void main() {
  group('isEmoticon', () {
    test('absmiddle / tiny size / emoticon URL mark a 表情', () {
      expect(
        Mv2RichText.isEmoticon(
          img('<img src="/static/img/heart_x.png" width="14" align="absmiddle">'),
        ),
        isTrue,
      );
      expect(
        Mv2RichText.isEmoticon(img('<img src="/static/img/smiles/aiya.png">')),
        isTrue,
      );
      expect(
        Mv2RichText.isEmoticon(
          img('<img src="https://www.v2ex.com/static/img/heart_x.png" width="14">'),
        ),
        isTrue,
      );
    });

    test('dimensionless external and explicitly large images are content', () {
      expect(
        Mv2RichText.isEmoticon(img('<img src="https://i.imgur.com/doge.png">')),
        isFalse,
      );
      expect(
        Mv2RichText.isEmoticon(
          img('<img src="/static/img/big.png" width="640">'),
        ),
        isFalse,
      );
    });
  });

  testWidgets('a Unicode-alt emoticon renders as the glyph itself', (
    tester,
  ) async {
    await pumpBody(
      tester,
      '<p>赞 <img src="/static/img/heart_20250818.png" width="14" '
      'align="absmiddle" alt="❤️"> 一个</p>',
    );
    expect(bodyTexts(), findsOneWidget);
    expect(plainText(tester), '赞 ❤️ 一个');
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('a small image stays inline inside one flowing paragraph', (
    tester,
  ) async {
    await pumpBody(
      tester,
      '<p>哈哈 <img src="/static/img/smiles/aiya.png" width="14"> 哈哈</p>',
      settle: false,
    );
    expect(bodyTexts(), findsOneWidget);
    // The image is a WidgetSpan *inside* the paragraph's Text.rich, not a
    // block sibling that would push the rest of the sentence to a new line.
    expect(
      find.descendant(of: bodyTexts(), matching: find.byType(CachedNetworkImage)),
      findsOneWidget,
    );
  });

  testWidgets('content images still take the block path', (tester) async {
    await pumpBody(
      tester,
      '<p>看图</p><img src="https://i.imgur.com/abc.png"><p>完毕</p>',
      settle: false,
    );
    expect(bodyTexts(), findsNWidgets(2));
    expect(
      find.descendant(of: bodyTexts(), matching: find.byType(CachedNetworkImage)),
      findsNothing,
    );
  });

  testWidgets('a linked emoticon keeps the glyph inline', (tester) async {
    await pumpBody(
      tester,
      '<p><a href="https://x.com"><img src="/static/img/heart_x.png" '
      'width="14" align="absmiddle" alt="❤️"></a></p>',
    );
    expect(bodyTexts(), findsOneWidget);
    expect(plainText(tester), '❤️');
  });

  testWidgets('a paragraph holding only an emoticon is not dropped', (
    tester,
  ) async {
    await pumpBody(
      tester,
      '<p>前</p><p><img src="/static/img/heart_x.png" width="14" '
      'align="absmiddle" alt="❤️"></p><p>后</p>',
    );
    expect(bodyTexts(), findsNWidgets(3));
    expect(
      bodyTexts().evaluate().map(
        (element) => (element.widget as Text).textSpan?.toPlainText() ?? '',
      ),
      contains(contains('❤️')),
    );
  });
}
