import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/ui/components/mv2_floating_tab_bar.dart';
import 'package:mv2/ui/components/mv2_trailing_rail.dart';
import 'package:mv2/ui/utils/mv2_breakpoints.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_container.dart';

/// The unfolded iPhone Duo hosts its chrome in the trailing safe-area strip
/// (the sensor-bar side where iOS parks the status bar): the shell renders a
/// vertical rail instead of the floating bottom bar. Every other device keeps
/// the floating bar.
void main() {
  const duoSize = Size(951, 669);
  // Measured on the unfolded inner display: leading 0, trailing 84, bottom 20.
  const duoPadding = EdgeInsets.only(right: 84, bottom: 20);

  /// What the mocked `mv2/native` channel reports for `horizontalSizeClass`.
  String? nativeSizeClass;

  setUp(() {
    mv2HorizontalSizeClass = null;
    nativeSizeClass = 'regular';
  });
  tearDown(() => mv2HorizontalSizeClass = null);

  Future<ProviderContainer> boot(
    WidgetTester tester,
    Size logicalSize, {
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    const dpr = 3.0;
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // Mock the native trait channel so `Mv2SizeClassSync` fills the global the
    // same way it does on the Duo (the test binding has no plugin).
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('mv2/native'),
      (MethodCall call) async =>
          call.method == 'horizontalSizeClass' ? nativeSizeClass : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('mv2/native'),
        null,
      ),
    );

    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = Size(
      logicalSize.width * dpr,
      logicalSize.height * dpr,
    );
    tester.view.viewPadding = FakeViewPadding(
      left: padding.left * dpr,
      top: padding.top * dpr,
      right: padding.right * dpr,
      bottom: padding.bottom * dpr,
    );
    // `MediaQuery.padding` reads the (already inset-subtracted) `view.padding`,
    // while the safe-area widgets read `view.viewPadding`; keep both in sync.
    tester.view.padding = FakeViewPadding(
      left: padding.left * dpr,
      top: padding.top * dpr,
      right: padding.right * dpr,
      bottom: padding.bottom * dpr,
    );
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [v2exApiProvider.overrideWithValue(fixtureApi())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const Mv2App()),
    );
    // Fixture providers resolve after ~250ms and the skeletons shimmer forever,
    // so pump in steps instead of settling.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  testWidgets('unfolded Duo moves page actions and tabs into the rail', (
    tester,
  ) async {
    await boot(tester, duoSize, padding: duoPadding);

    expect(find.byType(Mv2TrailingRail), findsOneWidget);
    expect(find.byType(Mv2FloatingTabBar), findsNothing);

    final rail = find.byType(Mv2TrailingRail);
    for (final label in <String>['搜索', '首页', '节点', '发布', '通知', '我的']) {
      expect(
        find.descendant(of: rail, matching: find.text(label)),
        findsOneWidget,
        reason: '«$label» should live in the rail',
      );
    }
    // Still two-pane: the rail is chrome, not a layout mode.
    expect(find.text('未选择主题'), findsOneWidget);
  });

  testWidgets('tablet without a trailing strip keeps the floating bar', (
    tester,
  ) async {
    await boot(tester, const Size(1200, 900));

    expect(find.byType(Mv2FloatingTabBar), findsOneWidget);
    expect(find.byType(Mv2TrailingRail), findsNothing);
  });

  testWidgets('phone keeps the floating bar even with a trailing inset', (
    tester,
  ) async {
    // Landscape iPhone: compact width class, so the rail never applies.
    nativeSizeClass = 'compact';
    await boot(
      tester,
      const Size(874, 402),
      padding: const EdgeInsets.only(left: 59, right: 59, bottom: 21),
    );

    expect(find.byType(Mv2TrailingRail), findsNothing);
    expect(find.byType(Mv2FloatingTabBar), findsOneWidget);
  });

  testWidgets('rail destinations switch branches like the bar does', (
    tester,
  ) async {
    await boot(tester, duoSize, padding: duoPadding);

    await tester.tap(
      find.descendant(
        of: find.byType(Mv2TrailingRail),
        matching: find.text('节点'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('发现感兴趣的内容社区'), findsOneWidget);
  });

  testWidgets('rail detection needs a regular, wide window with a strip', (
    tester,
  ) async {
    mv2HorizontalSizeClass = 'regular';

    Future<bool> probe(Size size, EdgeInsets padding) async {
      late bool result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size, padding: padding),
          child: Builder(
            builder: (BuildContext context) {
              result = mv2UsesTrailingRail(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    expect(await probe(duoSize, duoPadding), isTrue);
    // Same window, no sensor-bar strip (e.g. a mirrored / non-Duo display).
    expect(await probe(duoSize, EdgeInsets.zero), isFalse);
    // Symmetric insets are not a sensor-bar strip.
    expect(
      await probe(duoSize, const EdgeInsets.symmetric(horizontal: 59)),
      isFalse,
    );
    // Wide window with a strip, but not a regular-width device.
    mv2HorizontalSizeClass = 'compact';
    expect(await probe(duoSize, duoPadding), isFalse);
  });
}
