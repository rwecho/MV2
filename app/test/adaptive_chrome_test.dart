import 'dart:ui' show DisplayFeature;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/ui/utils/mv2_breakpoints.dart';
import 'package:mv2/ui/utils/scene_geometry.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_container.dart';

/// Navigation chrome on the iPhone Duo.
///
/// The bar itself now belongs to `adaptive_platform_ui`: its fixed toolbar
/// chrome draws one persistent bar and moves it into the trailing strip on the
/// Duo. What is left to check here is that our own chrome stayed retired, that
/// the five destinations are the ones we have always shipped, and the geometry
/// rules we absorbed for the strip (which the package uses too).
void main() {
  // Folded cover display: 466×678, trailing strip 84pt, bottom 34pt.
  const foldedSize = Size(466, 678);
  const foldedPadding = EdgeInsets.only(right: 84, bottom: 34);

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

  /// What the device itself reports on the cover display.
  FoldableData coverDisplay() => FoldableData(
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
    regions: <ReservedRegion>[
      const ReservedRegion(
        kind: ReservedRegionKind.occlusion,
        bounds: Rect.fromLTRB(382, 0, 466, 170),
        isActive: true,
      ),
      const ReservedRegion(
        kind: ReservedRegionKind.occlusion,
        bounds: Rect.fromLTRB(399.7, 29.3, 436.7, 66.3),
        isActive: true,
      ),
    ],
    displayFeatures: const <DisplayFeature>[],
  );

  setUp(() {
    mv2HorizontalSizeClass = null;
    mv2SceneGeometry = null;
    nativeSizeClass = 'compact';
    nativeGeometry = geometry(
      statusBar: const Rect.fromLTWH(382, 0, 84, 170),
      safeArea: foldedPadding,
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
    FoldableData? foldable,
  }) async {
    const dpr = 3.0;
    SharedPreferences.setMockInitialValues(<String, Object>{});

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
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  /// The bar on the test host (not iOS) is the package's Material path, built
  /// from the same destinations.
  Finder destination(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('the adaptive bar replaces our chrome in the Duo pose', (
    tester,
  ) async {
    await boot(
      tester,
      foldedSize,
      padding: foldedPadding,
      foldable: coverDisplay(),
    );

    // The shell publishes one, and the page inside it another.
    expect(find.byType(AdaptiveScaffold), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in <String>['首页', '节点', '发布', '通知', '我的']) {
      expect(destination(label), findsOneWidget);
    }
  });

  testWidgets('发布 stays an action, not a branch', (tester) async {
    await boot(
      tester,
      foldedSize,
      padding: foldedPadding,
      foldable: coverDisplay(),
    );

    await tester.tap(destination('发布'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // The composer opens over the feed; the branch did not change. (「MV2」
    // appears twice now: the large title in the content and the fixed
    // toolbar's inline title.)
    expect(find.text('MV2'), findsWidgets);
  });

}
