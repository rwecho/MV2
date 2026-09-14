import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_image_viewer.dart';
import 'package:mv2/ui/components/mv2_rich_text.dart';

/// Pumps a host page and opens the gallery through the real entry point.
///
/// `pumpAndSettle` is avoided throughout: the loading indicator animates until
/// the (never-completing, in tests) network image resolves.
Future<void> openGallery(WidgetTester tester, List<String> images) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: Mv2ThemeData.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showMv2ImageViewer(context, images: images),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 260));
}

double chromeOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.textContaining(' / '),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;
}

void main() {
  const images = <String>[
    'https://cdn.v2ex.com/a.png',
    'https://cdn.v2ex.com/b.png',
    'https://cdn.v2ex.com/c.png',
  ];

  testWidgets('opens full screen with a page counter', (tester) async {
    await openGallery(tester, images);

    expect(find.byType(Mv2ImageViewer), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('swiping pages through the gallery', (tester) async {
    await openGallery(tester, images);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('tapping toggles the chrome', (tester) async {
    await openGallery(tester, images);
    expect(chromeOpacity(tester), 1);

    await tester.tapAt(const Offset(400, 300));
    // The single tap waits out the double-tap window before it fires.
    await tester.pump(const Duration(milliseconds: 500));

    expect(chromeOpacity(tester), 0);
  });

  testWidgets('dragging down dismisses the viewer', (tester) async {
    await openGallery(tester, images);

    await tester.drag(find.byType(Mv2ImageViewer), const Offset(0, 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Mv2ImageViewer), findsNothing);
  });

  testWidgets('the close button dismisses the viewer', (tester) async {
    await openGallery(tester, images);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Mv2ImageViewer), findsNothing);
  });

  testWidgets('a single image hides the counter', (tester) async {
    await openGallery(tester, const <String>['https://cdn.v2ex.com/only.png']);

    expect(find.byType(Mv2ImageViewer), findsOneWidget);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('tapping a rich-text image opens it in the viewer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: const Scaffold(
          body: Mv2RichText(
            html: '<img src="https://cdn.v2ex.com/a.png">'
                '<img src="https://cdn.v2ex.com/b.png">',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CachedNetworkImage), findsNWidgets(2));

    await tester.tap(find.byType(CachedNetworkImage).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byType(Mv2ImageViewer), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('tapping the second image opens the gallery at that position', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: const Scaffold(
          body: Mv2RichText(
            html: '<img src="https://cdn.v2ex.com/a.png">'
                '<img src="https://cdn.v2ex.com/b.png">'
                '<img src="https://cdn.v2ex.com/c.png">',
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(CachedNetworkImage).at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('a rich-text image without a src is not tappable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: const Scaffold(body: Mv2RichText(html: '<img alt="no src">')),
      ),
    );
    await tester.pump();

    expect(find.byType(Mv2ImageViewer), findsNothing);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
