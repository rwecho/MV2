import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_container.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('selected Android tab uses MV2 colors in $brightness', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [v2exApiProvider.overrideWithValue(fixtureApi())],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const Mv2App()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));
      final nav = find.byType(NavigationBar);
      final colors = tester.element(nav).colors;
      expect(
        tester.widget<NavigationBar>(nav).indicatorColor,
        colors.accentSoft,
      );
      final selected = find.descendant(
        of: nav,
        matching: find.byIcon(Icons.home_rounded),
      );
      expect(IconTheme.of(tester.element(selected)).color, colors.accent);
      final label = find.descendant(of: nav, matching: find.text('首页'));
      expect(
        tester.widget<Text>(label).style?.color,
        colors.accent,
      );
      final nodes = find.descendant(
        of: nav,
        matching: find.byIcon(Icons.grid_view_outlined),
      );
      expect(IconTheme.of(tester.element(nodes)).color, colors.textSecondary);
    });
  }
}
