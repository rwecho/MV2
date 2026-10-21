import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_settings_row.dart';

void main() {
  testWidgets(
    'settings chevron stays at the right edge at phone and tablet widths',
    (tester) async {
      for (final width in [360.0, 720.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: Mv2ThemeData.light(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const Mv2SettingsRow(
                    label: '主题',
                    value: '浅色',
                    icon: Icons.wb_sunny_outlined,
                  ),
                ),
              ),
            ),
          ),
        );
        final rowRect = tester.getRect(find.byType(Mv2SettingsRow));
        final chevronRect = tester.getRect(
          find.byIcon(Icons.chevron_right_rounded),
        );
        expect(rowRect.right - chevronRect.right, 16);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
