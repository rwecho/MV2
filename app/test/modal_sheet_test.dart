import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_modal_sheet.dart';

/// Modal sheets on a wide window.
///
/// Material 3 caps modal bottom sheets at 640pt (`_BottomSheetDefaultsM3`), so
/// on the unfolded Duo's 951pt inner display ours sat in the middle with a
/// third of the window empty on either side. The theme lifts that cap to the
/// 宽 content width, which is a no-op on phones.
void main() {
  const duoInner = Size(951, 669);
  const contentKey = ValueKey<String>('sheet-content');

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = duoInner;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showMv2Sheet<void>(
                  context,
                  child: const SizedBox(
                    key: contentKey,
                    width: double.infinity,
                    height: 120,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a sheet spans the unfolded Duo instead of stopping at 640', (
    tester,
  ) async {
    await openSheet(tester);

    final width = tester.getSize(find.byKey(contentKey)).width;
    expect(width, duoInner.width);
    expect(width, greaterThan(640));
  });

  testWidgets('the content still fills a phone-width sheet', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showMv2Sheet<void>(
                  context,
                  child: const SizedBox(
                    key: contentKey,
                    width: double.infinity,
                    height: 120,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(contentKey)).width, 390);
  });
}
