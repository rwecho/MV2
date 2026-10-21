import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/parser/html_dom.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_rich_text.dart';

const encoded = '42282d203102273a232f322e276c212d2f';

void main() {
  test(
    'restores protected anchors and nested spans before text extraction',
    () {
      final document = parseHtmlDocument('''
      <a href="/cdn-cgi/l/email-protection" data-cfemail="$encoded">[email protected]</a>
      <a href="/cdn-cgi/l/email-protection#$encoded"><span class="__cf_email__" data-cfemail="$encoded">[email protected]</span></a>
      <a href="https://www.v2ex.com/cdn-cgi/l/email-protection#$encoded">[email protected]</a>
    ''');
      for (final anchor in document.querySelectorAll('a')) {
        expect(anchor.text, 'jobs@example.com');
        expect(anchor.attributes['href'], 'mailto:jobs@example.com');
      }
    },
  );

  test('preserves malformed payloads and ordinary links', () {
    final document = parseHtmlDocument('''
      <a href="/cdn-cgi/l/email-protection" data-cfemail="xyz">protected</a>
      <a href="https://example.com">example</a>
    ''');
    expect(document.querySelector('a')!.text, 'protected');
    expect(
      document.querySelectorAll('a').last.attributes['href'],
      'https://example.com',
    );
  });

  testWidgets('cached protected HTML displays email and taps a mailto link', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: Mv2RichText(
            html:
                '<a href="/cdn-cgi/l/email-protection" data-cfemail="$encoded">[email protected]</a>',
            onLinkTap: (href) => tapped = href,
          ),
        ),
      ),
    );
    expect(find.text('jobs@example.com', findRichText: true), findsOneWidget);
    expect(find.text('[email protected]', findRichText: true), findsNothing);
    await tester.tap(find.text('jobs@example.com', findRichText: true));
    expect(tapped, 'mailto:jobs@example.com');
  });
}
