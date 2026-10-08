import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/design_system/effects/mv2_glass.dart';
import 'package:mv2/ui/components/mv2_floating_tab_bar.dart';
import 'package:mv2/ui/components/mv2_trailing_chrome.dart';
import 'package:mv2/ui/components/topic_item.dart';
import 'package:mv2/ui/utils/mv2_breakpoints.dart';
import 'package:mv2/ui/utils/scene_geometry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_container.dart';

/// The iPhone Duo keeps a wide safe-area strip along its sensor-bar edge in
/// both states. The shell hosts its chrome (page actions + the five
/// destinations) in a vertical rail inside that strip instead of the floating
/// bottom bar, and it must stay clear of the system's own status column.
void main() {
  // Folded cover display: 466×678, trailing strip 84pt, bottom 34pt.
  const foldedSize = Size(466, 678);
  const foldedPadding = EdgeInsets.only(right: 84, bottom: 34);
  // Unfolded inner display: 951×669, trailing strip 84pt, no bottom inset.
  const unfoldedSize = Size(951, 669);
  const unfoldedPadding = EdgeInsets.only(right: 84);

  /// The status column iOS draws inside the trailing strip while unfolded —
  /// the rail has to start below it.
  const statusColumnHeight = 220.0;

  String? nativeSizeClass;
  Map<Object?, Object?>? nativeGeometry;

  Map<Object?, Object?> geometry({
    required Rect statusBar,
    required EdgeInsets safeArea,
  }) => <Object?, Object?>{
    'statusBar': <Object?, Object?>{
      'x': statusBar.left,
      'y': statusBar.top,
      'width': statusBar.width,
      'height': statusBar.height,
    },
    'safeArea': <Object?, Object?>{
      'top': safeArea.top,
      'left': safeArea.left,
      'bottom': safeArea.bottom,
      'right': safeArea.right,
    },
  };

  setUp(() {
    mv2HorizontalSizeClass = null;
    mv2SceneGeometry = null;
    nativeSizeClass = 'compact';
    nativeGeometry = geometry(
      statusBar: const Rect.fromLTWH(867, 0, 84, statusColumnHeight),
      safeArea: unfoldedPadding,
    );
  });
  tearDown(() {
    mv2HorizontalSizeClass = null;
    mv2SceneGeometry = null;
  });

  Future<ProviderContainer> boot(
    WidgetTester tester,
    Size logicalSize, {
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    const dpr = 3.0;
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // Mock the native channel the same way UIKit answers on the Duo; the test
    // binding has no plugin.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('mv2/native'),
      (MethodCall call) async => switch (call.method) {
        'horizontalSizeClass' => nativeSizeClass,
        'uiGeometry' => nativeGeometry,
        _ => null,
      },
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
    // `MediaQuery.padding` reads the (inset-subtracted) `view.padding`, while
    // the safe-area widgets read `view.viewPadding`; keep both in sync.
    tester.view.padding = FakeViewPadding(
      left: padding.left * dpr,
      top: padding.top * dpr,
      right: padding.right * dpr,
      bottom: padding.bottom * dpr,
    );
    tester.view.viewPadding = FakeViewPadding(
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
    nativeSizeClass = 'regular';
    await boot(tester, unfoldedSize, padding: unfoldedPadding);

    expect(find.byType(Mv2TrailingChrome), findsOneWidget);
    expect(find.byType(Mv2FloatingTabBar), findsNothing);

    final chrome = find.byType(Mv2TrailingChrome);
    // Toolbar: circular icon buttons (Apple's shape for this edge).
    expect(
      find.descendant(
        of: chrome,
        matching: find.byIcon(Icons.search_rounded),
      ),
      findsOneWidget,
    );
    // Tab bar: the five destinations, labelled.
    for (final label in <String>['首页', '节点', '发布', '通知', '我的']) {
      expect(
        find.descendant(of: chrome, matching: find.text(label)),
        findsOneWidget,
        reason: '«$label» should live in the strip',
      );
    }
    // Still two-pane: the rail is chrome, not a layout mode.
    expect(find.text('未选择主题'), findsOneWidget);
  });

  testWidgets('rail starts below the system status column', (tester) async {
    nativeSizeClass = 'regular';
    await boot(tester, unfoldedSize, padding: unfoldedPadding);

    // The engine-reported obstruction (220) wins over the measured floor (96).
    expect(
      tester.widget<Mv2TrailingChrome>(find.byType(Mv2TrailingChrome)).topInset,
      statusColumnHeight,
    );
    // The glass column starts after the system chrome, and the controls sit in
    // the lower half of the strip — the top of it belongs to the system.
    expect(
      tester
          .getTopLeft(
            find
                .descendant(
                  of: find.byType(Mv2TrailingChrome),
                  matching: find.byType(Mv2GlassSurface),
                )
                .first,
          )
          .dy,
      greaterThanOrEqualTo(statusColumnHeight),
    );
    // Bottom-anchored, so the strip's top — where the system draws its own
    // column — is left empty and the last destination hugs the bottom edge.
    // Two groups: page actions below the system column, destinations at the
    // bottom of the strip.
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: find.byType(Mv2TrailingChrome),
              matching: find.byIcon(Icons.search_rounded),
            ),
          )
          .dy,
      greaterThanOrEqualTo(statusColumnHeight),
      reason: 'page actions must clear the system column',
    );
    expect(
      tester
          .getBottomLeft(
            find.descendant(
              of: find.byType(Mv2TrailingChrome),
              matching: find.text('我的'),
            ),
          )
          .dy,
      greaterThan(unfoldedSize.height - 60),
      reason: 'destinations sit at the bottom of the strip',
    );
  });

  testWidgets('folded cover display also hosts the rail', (tester) async {
    // Folded: compact width, single column, but the same trailing strip.
    nativeGeometry = geometry(
      statusBar: const Rect.fromLTWH(0, 0, 466, 54),
      safeArea: foldedPadding,
    );
    await boot(tester, foldedSize, padding: foldedPadding);

    expect(find.byType(Mv2TrailingChrome), findsOneWidget);
    expect(find.byType(Mv2FloatingTabBar), findsNothing);
    expect(
      tester.widget<Mv2TrailingChrome>(find.byType(Mv2TrailingChrome)).topInset,
      duoStatusColumnInset,
    );
  });

  testWidgets('topic detail hands its actions to the rail', (tester) async {
    await boot(tester, foldedSize, padding: foldedPadding);

    final chrome = find.byType(Mv2TrailingChrome);
    // Default chrome before a topic is open.
    expect(
      find.descendant(
        of: chrome,
        matching: find.byIcon(Icons.search_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(TopicItem).first);
    // The pushed detail needs its own fixture load, then one more frame for the
    // page to publish its actions into the strip.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Window chrome survives the push, and the page's own actions replace the
    // defaults in that strip (Apple's trailing-pane controls).
    for (final icon in <IconData>[
      Icons.star_border_rounded,
      Icons.favorite_border_rounded,
      Icons.more_horiz_rounded,
    ]) {
      expect(
        find.descendant(of: chrome, matching: find.byIcon(icon)),
        findsOneWidget,
        reason: '«$icon» should be offered by the strip toolbar',
      );
    }
    expect(
      find.descendant(
        of: chrome,
        matching: find.byIcon(Icons.search_rounded),
      ),
      findsNothing,
    );
    // The ellipsis is reserved for overflow and lives in exactly one place: the
    // page's own top-bar menu steps aside while the strip is present.
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });

  testWidgets('the toolbar follows the page', (tester) async {
    await boot(tester, foldedSize, padding: foldedPadding);
    final chrome = find.byType(Mv2TrailingChrome);

    // Feed: its header search moves into the strip.
    expect(
      find.descendant(of: chrome, matching: find.byIcon(Icons.search_rounded)),
      findsOneWidget,
    );

    Future<void> switchTo(String label) async {
      await tester.tap(find.descendant(of: chrome, matching: find.text(label)));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    // 节点 ships 筛选节点; 我的 ships 设置. Each replaces the previous page's
    // action, which is the point of hosting the toolbar in the strip.
    await switchTo('节点');
    expect(
      find.descendant(
        of: chrome,
        matching: find.byIcon(Icons.filter_list_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chrome, matching: find.byIcon(Icons.search_rounded)),
      findsNothing,
    );

    await switchTo('我的');
    expect(
      find.descendant(
        of: chrome,
        matching: find.byIcon(Icons.settings_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: chrome,
        matching: find.byIcon(Icons.filter_list_rounded),
      ),
      findsNothing,
    );
  });

  testWidgets('tablet without a trailing strip keeps the floating bar', (
    tester,
  ) async {
    nativeSizeClass = 'regular';
    await boot(tester, const Size(1200, 900));

    expect(find.byType(Mv2FloatingTabBar), findsOneWidget);
    expect(find.byType(Mv2TrailingChrome), findsNothing);
  });

  testWidgets('phone with symmetric insets keeps the floating bar', (
    tester,
  ) async {
    // Landscape iPhone: the island insets are symmetric, so no sensor-bar strip.
    await boot(
      tester,
      const Size(874, 402),
      padding: const EdgeInsets.symmetric(horizontal: 59),
    );

    expect(find.byType(Mv2TrailingChrome), findsNothing);
    expect(find.byType(Mv2FloatingTabBar), findsOneWidget);
  });

  testWidgets('rail destinations switch branches like the bar does', (
    tester,
  ) async {
    nativeSizeClass = 'regular';
    await boot(tester, unfoldedSize, padding: unfoldedPadding);

    await tester.tap(
      find.descendant(
        of: find.byType(Mv2TrailingChrome),
        matching: find.text('节点'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('发现感兴趣的内容社区'), findsOneWidget);
  });

  testWidgets('strip detection needs an asymmetric trailing inset', (
    tester,
  ) async {
    Future<(double, bool, double)> probe(
      Size size,
      EdgeInsets padding, {
      List<DisplayFeature> features = const <DisplayFeature>[],
    }) async {
      late double strip;
      late bool rail;
      late double top;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: padding,
            displayFeatures: features,
          ),
          child: Builder(
            builder: (BuildContext context) {
              strip = mv2TrailingStripWidth(context);
              rail = mv2UsesTrailingRail(context);
              top = mv2RailTopInset(context, strip);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return (strip, rail, top);
    }

    mv2SceneGeometry = Mv2SceneGeometry.fromMap(
      geometry(
        statusBar: const Rect.fromLTWH(867, 0, 84, statusColumnHeight),
        safeArea: unfoldedPadding,
      ),
    );

    // Duo strip → strip + rail, and the rail clears the status column.
    expect(
      await probe(unfoldedSize, unfoldedPadding),
      (84.0, true, statusColumnHeight),
    );
    // Symmetric insets (landscape iPhone) → no strip.
    expect(
      await probe(unfoldedSize, const EdgeInsets.symmetric(horizontal: 59)),
      (0.0, false, 0.0),
    );
    // Too small to be the sensor-bar strip.
    expect(
      await probe(unfoldedSize, const EdgeInsets.only(right: 34)),
      (0.0, false, 0.0),
    );
    // No native geometry yet → the measured system-column floor applies.
    mv2SceneGeometry = null;
    expect(
      await probe(unfoldedSize, unfoldedPadding),
      (84.0, true, duoStatusColumnInset),
    );

    // Once Flutter populates display features (flutter/flutter#193025) the
    // engine-reported reserved strip wins over the safe-area fallback — and a
    // second obstruction hugging the top of that strip becomes the rail's top
    // inset. Zero app-side change beyond this file.
    const strip = DisplayFeature(
      bounds: Rect.fromLTWH(867, 0, 84, 669),
      type: DisplayFeatureType.cutout,
      state: DisplayFeatureState.unknown,
    );
    expect(
      await probe(unfoldedSize, EdgeInsets.zero, features: const [strip]),
      (84.0, true, duoStatusColumnInset),
    );
    const island = DisplayFeature(
      bounds: Rect.fromLTWH(867, 0, 84, 180),
      type: DisplayFeatureType.cutout,
      state: DisplayFeatureState.unknown,
    );
    expect(
      await probe(unfoldedSize, EdgeInsets.zero, features: const [strip, island]),
      (84.0, true, 180.0),
    );
  });
}
