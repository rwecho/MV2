import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/ui/utils/mv2_breakpoints.dart';

/// The two-pane decision combines the width breakpoint with (on iOS) the
/// UIKit horizontal size class cached from the native bridge.
///
/// Key distinction the width alone cannot make: iPhone Duo unfolded is 871pt
/// wide — almost identical to a landscape iPhone (~874pt). The size class
/// (regular vs compact) tells them apart; iPad portrait widths (744 / 834)
/// are regular as well, so the explicit 850 floor keeps them single-column.
void main() {
  tearDown(() => mv2HorizontalSizeClass = null);

  /// Evaluates [mv2IsTwoPane] in a real widget tree at [width] logical px.
  Future<bool> twoPaneAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late bool twoPane;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            twoPane = mv2IsTwoPane(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return twoPane;
  }

  testWidgets('iPhone Duo unfolded (871pt, regular) enters two-pane', (
    tester,
  ) async {
    mv2HorizontalSizeClass = 'regular';
    expect(await twoPaneAt(tester, 871), isTrue);
  });

  testWidgets('landscape iPhone (874pt, compact) stays single-column', (
    tester,
  ) async {
    mv2HorizontalSizeClass = 'compact';
    expect(await twoPaneAt(tester, 874), isFalse);
  });

  testWidgets('iPad 11" portrait (834pt, regular) stays single-column', (
    tester,
  ) async {
    mv2HorizontalSizeClass = 'regular';
    expect(await twoPaneAt(tester, 834), isFalse);
  });

  testWidgets('iPad mini portrait (744pt, regular) stays single-column', (
    tester,
  ) async {
    mv2HorizontalSizeClass = 'regular';
    expect(await twoPaneAt(tester, 744), isFalse);
  });

  testWidgets('iPhone Duo folded (386pt) never enters two-pane', (
    tester,
  ) async {
    mv2HorizontalSizeClass = 'regular';
    expect(await twoPaneAt(tester, 386), isFalse);
  });

  testWidgets('wide iPad (1200pt) is two-pane regardless of size class', (
    tester,
  ) async {
    mv2HorizontalSizeClass = 'compact'; // trait read before wide resize
    expect(await twoPaneAt(tester, 1200), isTrue);
  });

  testWidgets('size class unknown (non-iOS) falls back to width breakpoint', (
    tester,
  ) async {
    mv2HorizontalSizeClass = null;
    expect(await twoPaneAt(tester, 871), isFalse);
    expect(await twoPaneAt(tester, 1024), isTrue);
  });
}