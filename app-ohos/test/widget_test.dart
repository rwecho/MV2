import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_floating_tab_bar.dart';

void main() {
  Finder tab(String label) => find.descendant(
    of: find.byType(Mv2FloatingTabBar),
    matching: find.text(label),
  );

  testWidgets('boots into the feed branch with the floating tab bar', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: Mv2App()));
    await tester.pump();
    // Let the fixture FutureProviders (250ms) fire so no timer outlives the
    // widget tree.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(Mv2FloatingTabBar), findsOneWidget);
    for (final label in <String>['首页', '节点', '发布', '通知', '我的']) {
      expect(tab(label), findsOneWidget);
    }

    // Feed header comes from Mv2PageHeader.
    expect(find.text('MV2'), findsOneWidget);
    expect(find.text('更好的开发者社区'), findsOneWidget);
  });

  testWidgets('tapping the 节点 destination switches branches', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: Mv2App()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(tab('节点'));
    // Feed/nodes providers resolve after an artificial 250ms delay and the
    // list renders shaking skeletons, so pump in steps instead of settling.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('发现感兴趣的内容社区'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('light theme exposes the MV2 tokens', (tester) async {
    late Mv2Theme tokens;
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Builder(
          builder: (context) {
            tokens = context.mv2;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(tokens.colors.background, const Color(0xFFF7F8FA));
    expect(tokens.colors.accent, const Color(0xFF2563EB));
    expect(tokens.isDark, isFalse);
    expect(tokens.typography.scale, 1);
  });
}
