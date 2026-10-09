import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/ui/components/mv2_page_scaffold.dart';

/// Pages under `Mv2PageScaffold` keep a Material ancestor.
///
/// `adaptive_platform_ui`'s iOS 26+ scaffold is a CupertinoPageScaffold,
/// which provides no Material ancestor — Material widgets on the page
/// (TextField, DropdownButton, …) crash with "No Material widget found" on
/// device while the macOS test host takes the package's Material branch and
/// never sees it (the login page shipped exactly that). This pins the
/// transparency-Material wrap the scaffold puts around the body.
void main() {
  const childKey = ValueKey<String>('page-child');

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Mv2PageScaffold(
            child: const TextField(key: childKey),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('the page body renders its Material-requiring children', (
    tester,
  ) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a Material ancestor sits above the page body', (tester) async {
    await pump(tester);
    expect(
      find.ancestor(
        of: find.byKey(childKey),
        matching: find.byType(Material),
      ),
      findsWidgets,
    );
  });
}
