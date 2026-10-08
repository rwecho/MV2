import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
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

  /// A synthetic fold snapshot: the platform channel that normally carries it
  /// does not exist in the test binding.
  FoldableData snapshot(List<ReservedRegion> regions) => FoldableData(
    capabilities: const FoldableCapabilities(
      supportLevel: FoldableSupportLevel.available,
      isFoldable: true,
      hingeApiPresent: true,
      regionApiPresent: true,
      angleUnitVerified: true,
      strategy: 'test',
    ),
    status: HingeStatus.closed,
    angleDegrees: 0,
    regions: regions,
    displayFeatures: const <DisplayFeature>[],
  );

  ReservedRegion occlusion(Rect bounds, {bool active = true}) =>
      ReservedRegion(
        kind: ReservedRegionKind.occlusion,
        bounds: bounds,
        isActive: active,
      );

  Future<ProviderContainer> boot(
    WidgetTester tester,
    Size logicalSize, {
    EdgeInsets padding = EdgeInsets.zero,
    FoldableData? foldable,
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
      UncontrolledProviderScope(
        container: container,
        child: Mv2App(
          debugFoldable: foldable == null
              ? null
              : Stream<FoldableData>.value(foldable),
          debugFold: foldable,
        ),
      ),
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
    // Tab bar: the five destinations as icon tiles.
    for (final icon in <IconData>[
      // 首页 is the selected tab here, so it renders its active icon.
      Icons.home_rounded,
      Icons.grid_view_outlined,
      Icons.add_rounded,
      Icons.notifications_none_rounded,
      Icons.person_outline_rounded,
    ]) {
      expect(
        find.descendant(of: chrome, matching: find.byIcon(icon)),
        findsOneWidget,
        reason: '«$icon» should live in the strip',
      );
    }
    // Still two-pane: the rail is chrome, not a layout mode.
    expect(find.text('未选择主题'), findsOneWidget);
  });

  testWidgets('rail starts below the reported status cluster', (tester) async {
    nativeSizeClass = 'regular';
    // The device reports its status cluster as an occlusion region inside the
    // strip; that reading — not a measured constant — sets the top clearance.
    await boot(
      tester,
      unfoldedSize,
      padding: unfoldedPadding,
      foldable: snapshot(<ReservedRegion>[
        occlusion(const Rect.fromLTWH(867, 0, 84, statusColumnHeight)),
      ]),
    );

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
    // The tab capsule is pinned to the bottom of the bar, above the bottom
    // clearance — the arrangement the reference Duo bar uses.
    final destinations = tester.getRect(
      find.descendant(
        of: find.byType(Mv2TrailingChrome),
        matching: find.byType(Mv2GlassSurface),
      ).last,
    );
    final toolbar = tester.getRect(
      find.descendant(
        of: find.byType(Mv2TrailingChrome),
        matching: find.byType(Mv2GlassSurface),
      ).first,
    );
    expect(
      destinations.center.dy,
      greaterThan(toolbar.bottom),
      reason: 'tab bar sits below the toolbar',
    );
    expect(
      destinations.bottom,
      lessThanOrEqualTo(unfoldedSize.height),
      reason: 'tab bar stays inside the bar',
    );
    expect(
      destinations.bottom,
      greaterThan(unfoldedSize.height - 60),
      reason: 'tab bar is pinned to the bottom of the bar',
    );
  });

  testWidgets('folded cover display also hosts the rail', (tester) async {
    // Folded: compact width, single column, but the same trailing strip.
    nativeGeometry = geometry(
      statusBar: const Rect.fromLTWH(0, 0, 466, 54),
      safeArea: foldedPadding,
    );
    await boot(
      tester,
      foldedSize,
      padding: foldedPadding,
      // Exactly what the device reports on the cover display.
      foldable: snapshot(<ReservedRegion>[
        occlusion(const Rect.fromLTRB(382, 0, 466, 170)),
        occlusion(const Rect.fromLTRB(399.7, 29.3, 436.7, 66.3)),
      ]),
    );

    expect(find.byType(Mv2TrailingChrome), findsOneWidget);
    expect(find.byType(Mv2FloatingTabBar), findsNothing);
    expect(
      tester.widget<Mv2TrailingChrome>(find.byType(Mv2TrailingChrome)).topInset,
      170,
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

  testWidgets('toolbar and tab bar sit on the system band axis', (tester) async {
    await boot(tester, foldedSize, padding: foldedPadding);
    final chrome = find.byType(Mv2TrailingChrome);

    // The band is the 84pt strip plus the 12pt bezel inset, so its centre is
    // 466 - (84 + 12) / 2 = 418pt — the camera's own centre on this device.
    final axis = foldedSize.width - (84 + mv2DuoBarBezelInset) / 2;
    expect(axis, isNot(closeTo(foldedSize.width - 84 / 2, 1.0)));

    final discs = find.descendant(
      of: chrome,
      matching: find.byType(Mv2GlassSurface),
    );
    // First disc is the toolbar button, last is the tab capsule.
    final button = tester.getRect(discs.first);
    expect(button.width, closeTo(mv2DuoCapsuleWidth, 0.5));
    expect(button.center.dx, closeTo(axis, 0.5));

    final tabBar = tester.getRect(discs.last);
    expect(tabBar.width, closeTo(mv2DuoCapsuleWidth, 0.5));
    expect(tabBar.center.dx, closeTo(axis, 0.5));
  });

  testWidgets('the toolbar follows the page', (tester) async {
    await boot(tester, foldedSize, padding: foldedPadding);
    final chrome = find.byType(Mv2TrailingChrome);

    // Feed: its header search moves into the strip.
    expect(
      find.descendant(of: chrome, matching: find.byIcon(Icons.search_rounded)),
      findsOneWidget,
    );

    Future<void> switchTo(IconData icon) async {
      await tester.tap(find.descendant(of: chrome, matching: find.byIcon(icon)));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    // 节点 ships 筛选节点; 我的 ships 设置. Each replaces the previous page's
    // action, which is the point of hosting the toolbar in the strip.
    await switchTo(Icons.grid_view_outlined);
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

    await switchTo(Icons.person_outline_rounded);
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
        matching: find.byIcon(Icons.grid_view_outlined),
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
            // The bar side is read from the *view* padding, exactly as the
            // reference implementation does (it survives a SafeArea above).
            viewPadding: padding,
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

    // Duo strip → strip + chrome, and the chrome clears the status cluster.
    // The clearance now comes from the reported occlusion region (or the
    // 170pt cluster fallback when nothing has arrived) rather than from
    // `statusBarFrame`, which reports ~2pt on this device.
    expect(
      await probe(unfoldedSize, unfoldedPadding),
      (84.0, true, mv2DuoStatusClusterFallbackHeight),
    );
    // Symmetric insets (landscape iPhone) → no strip.
    expect(
      await probe(unfoldedSize, const EdgeInsets.symmetric(horizontal: 59)),
      (0.0, false, 0.0),
    );
    // A single side inset is what the system reserves, whatever its size
    // (the reference DuoLayout accepts any; phones never report one).
    expect(
      await probe(unfoldedSize, const EdgeInsets.only(right: 34)),
      (34.0, true, mv2DuoStatusClusterFallbackHeight),
    );
    // No fold reading yet → the status-cluster fallback (the region is 170pt
    // deep on this device) still keeps controls out of it.
    mv2SceneGeometry = null;
    expect(
      await probe(unfoldedSize, unfoldedPadding),
      (84.0, true, mv2DuoStatusClusterFallbackHeight),
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
      (84.0, true, mv2DuoStatusClusterFallbackHeight),
    );
  });
}
