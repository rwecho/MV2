import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_rich_text.dart';

/// `@username` mentions resolve to the in-app member route by default, but a
/// reply surface can intercept them and treat the tap as "reply to that
/// member's comment" instead.
void main() {
  group('Mv2RichText.internalRoute', () {
    test('member links and @mentions stay in-app', () {
      expect(Mv2RichText.internalRoute('/member/livid'), '/member/livid');
      expect(
        Mv2RichText.internalRoute('https://www.v2ex.com/member/livid'),
        '/member/livid',
      );
      // Usernames with URL-unsafe characters survive the round-trip.
      expect(Mv2RichText.internalRoute('/member/a%20b'), '/member/a%20b');
    });

    test('topic and node links stay in-app', () {
      // A `#reply4` anchor carries the floor so the topic page can locate it.
      expect(Mv2RichText.internalRoute('/t/123#reply4'), '/topic/123?floor=4');
      expect(Mv2RichText.internalRoute('/t/123'), '/topic/123');
      expect(Mv2RichText.internalRoute('/go/programmer'), '/node/programmer');
    });

    test('other links are external', () {
      expect(Mv2RichText.internalRoute('https://example.com/x'), isNull);
      expect(Mv2RichText.internalRoute('/about'), isNull);
    });
  });

  group('Mv2RichText.mentionUsername', () {
    test('extracts the mentioned username', () {
      expect(Mv2RichText.mentionUsername('/member/livid'), 'livid');
      expect(
        Mv2RichText.mentionUsername('https://www.v2ex.com/member/livid'),
        'livid',
      );
      expect(Mv2RichText.mentionUsername('/t/123'), isNull);
      expect(Mv2RichText.mentionUsername('https://example.com'), isNull);
    });
  });

  testWidgets('tapping a member mention reaches the link handler', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: Center(
            child: Mv2RichText(
              html: '<a href="/member/livid">@livid</a>',
              onLinkTap: (String href) => tapped = href,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Text).first);
    await tester.pump();

    expect(tapped, '/member/livid');
    expect(Mv2RichText.internalRoute(tapped!), '/member/livid');
  });

  testWidgets('onMentionTap intercepts a mention before navigation', (
    tester,
  ) async {
    String? mentioned;
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: Center(
            child: Mv2RichText(
              html: '<a href="/member/livid">@livid</a>',
              onMentionTap: (String username) => mentioned = username,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Text).first);
    await tester.pump();

    expect(mentioned, 'livid');
  });

  group('@user #N floor reference', () {
    testWidgets('renders a jump chip and taps to the floor', (tester) async {
      int? jumped;
      await tester.pumpWidget(
        MaterialApp(
          theme: Mv2ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: Mv2RichText(
                html: '<a href="/member/QingXuJiaZhi">@QingXuJiaZhi</a> #5 说得对',
                onMentionTap: (_) {},
                onFloorRefTap: (int floor) => jumped = floor,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('#5'), findsOneWidget);
      // The trailing text survives; only `#5` is replaced by the chip.
      expect(find.textContaining('说得对'), findsOneWidget);

      await tester.tap(find.text('#5'));
      await tester.pump();
      expect(jumped, 5);
    });

    testWidgets('accepts #5楼 and #5L suffixes', (tester) async {
      for (final suffix in <String>['楼', 'L']) {
        await tester.pumpWidget(
          MaterialApp(
            theme: Mv2ThemeData.light(),
            home: Scaffold(
              body: Center(
                child: Mv2RichText(
                  html: '<a href="/member/livid">@livid</a> #7$suffix 好的',
                  onFloorRefTap: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('#7'), findsOneWidget);
      }
    });

    testWidgets('handles V2EX markup where @ sits outside the link', (
      tester,
    ) async {
      // The bundled topic fixture uses `@<a>user</a>`, not `<a>@user</a>`.
      int? jumped;
      await tester.pumpWidget(
        MaterialApp(
          theme: Mv2ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: Mv2RichText(
                html: '@<a href="/member/sentinelK">sentinelK</a> #2 同意',
                onMentionTap: (_) {},
                onFloorRefTap: (int floor) => jumped = floor,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('#2'), findsOneWidget);
      await tester.tap(find.text('#2'));
      await tester.pump();
      expect(jumped, 2);
    });

    testWidgets('keeps plain text when no floor handler is wired', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: Mv2ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: Mv2RichText(
                html: '<a href="/member/livid">@livid</a> #5',
                onMentionTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('#5'), findsNothing);
      expect(find.textContaining('#5'), findsOneWidget);
    });

    testWidgets('a bare #N is a floor reference even without a mention', (
      tester,
    ) async {
      int? jumped;
      await tester.pumpWidget(
        MaterialApp(
          theme: Mv2ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: Mv2RichText(
                html: '<p>见 #7 的说明</p>',
                onFloorRefTap: (int floor) => jumped = floor,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('#7'), findsOneWidget);
      await tester.tap(find.text('#7'));
      await tester.pump();
      expect(jumped, 7);
    });

    testWidgets('tapping the mention of `@user #N` jumps instead of replying', (
      tester,
    ) async {
      int? jumped;
      String? mentioned;
      await tester.pumpWidget(
        MaterialApp(
          theme: Mv2ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: Mv2RichText(
                html: '@<a href="/member/sentinelK">sentinelK</a> #2 同意',
                onMentionTap: (String username) => mentioned = username,
                onFloorRefTap: (int floor) => jumped = floor,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The name is the big tap target; it must jump, not open the composer.
      // Mentions live inside `Text.rich`, so tap the span by text range.
      await tester.tapOnText(find.textRange.ofSubstring('sentinelK'));
      await tester.pump();
      expect(jumped, 2);
      expect(mentioned, isNull);
    });
  });

  group('@ mention colouring', () {
    Future<void> pumpMention(
      WidgetTester tester,
      String html, {
      void Function(String)? onMentionTap,
      void Function(int)? onFloorRefTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: Mv2ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: Mv2RichText(
                html: html,
                onMentionTap: onMentionTap,
                onFloorRefTap: onFloorRefTap,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The inline spans of the single `Text.rich` the fragment produces.
    List<TextSpan> spans(WidgetTester tester) {
      final text = tester.widget<Text>(
        find
            .descendant(of: find.byType(Mv2RichText), matching: find.byType(Text))
            .first,
      );
      return (text.textSpan! as TextSpan)
          .children!
          .whereType<TextSpan>()
          .toList();
    }

    testWidgets('the literal @ is coloured like the username', (tester) async {
      await pumpMention(tester, '@<a href="/member/kernel">kernel</a> 你好');

      final at = spans(tester).firstWhere((span) => span.text == '@');
      final name = spans(tester).firstWhere((span) => span.text == 'kernel');

      expect(at.style?.color, isNotNull);
      expect(at.style?.color, name.style?.color);
    });

    testWidgets('text before the mention is preserved', (tester) async {
      await pumpMention(tester, '你好 @<a href="/member/kernel">kernel</a>');

      final joined = spans(tester).map((span) => span.text ?? '').join();
      expect(joined, contains('你好'));
      expect(joined, contains('@kernel'));
    });

    testWidgets('tapping the @ reaches the mention handler', (tester) async {
      String? mentioned;
      await pumpMention(
        tester,
        '@<a href="/member/kernel">kernel</a> 你好',
        onMentionTap: (String username) => mentioned = username,
      );

      await tester.tapOnText(find.textRange.ofSubstring('@'));
      await tester.pump();

      expect(mentioned, 'kernel');
    });

    testWidgets('tapping the @ of `@user #N` jumps to the floor', (
      tester,
    ) async {
      int? jumped;
      String? mentioned;
      await pumpMention(
        tester,
        '@<a href="/member/kernel">kernel</a> #3 同意',
        onMentionTap: (String username) => mentioned = username,
        onFloorRefTap: (int floor) => jumped = floor,
      );

      await tester.tapOnText(find.textRange.ofSubstring('@'));
      await tester.pump();

      expect(jumped, 3);
      expect(mentioned, isNull);
    });
  });
}
