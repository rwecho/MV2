import 'dart:math' as math;
import 'dart:ui' show DisplayFeature;

import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

/// Window-level chrome scope.
///
/// The trailing strip is *window* chrome (like the system status column): it
/// must survive route pushes, so `Mv2WindowChromeHost` renders it above the
/// router and publishes its measurements here. Descendants read them instead of
/// the raw safe area, because the host already subtracts the strip from the
/// content's media padding — without this, pages would reserve it twice.
class Mv2WindowChromeScope extends InheritedWidget {
  const Mv2WindowChromeScope({
    super.key,
    required this.stripWidth,
    required this.topInset,
    required super.child,
  });

  /// Width of the trailing strip, 0 when the window has none.
  final double stripWidth;

  /// Height the system's own column occupies at the top of the strip.
  final double topInset;

  static Mv2WindowChromeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Mv2WindowChromeScope>();

  @override
  bool updateShouldNotify(Mv2WindowChromeScope oldWidget) =>
      oldWidget.stripWidth != stripWidth || oldWidget.topInset != topInset;
}

/// Trailing strip implied by [padding]: the Duo reserves one edge wider than
/// the other (84pt vs 0 in both of its states); phones are symmetric.
double mv2StripWidthFrom(EdgeInsets padding) {
  if (padding.right < trailingRailMinInset) return 0;
  if (padding.right <= padding.left) return 0;
  return padding.right;
}

/// Trailing safe-area strip (logical px) from which on the window clearly
/// reserves the iPhone Duo's sensor-bar edge.
///
/// Measured on both Duo states (folded cover display 466×678 and unfolded inner
/// display 951×669): trailing inset 84pt while the leading inset is 0. Phones
/// report symmetric insets in landscape (or a top-only inset in portrait), so
/// they never reach the threshold.
const double trailingRailMinInset = 60.0;

class Mv2SceneGeometry {
  const Mv2SceneGeometry({
    required this.statusBarFrame,
    required this.safeArea,
  });

  /// Where the system draws the status bar, in scene (logical) coordinates.
  ///
  /// On the Duo this is the vertical column in the trailing strip: its `bottom`
  /// is how far the system chrome reaches down that strip. Empty when hidden.
  final Rect statusBarFrame;

  /// Safe area the window keeps — mirrors `MediaQuery.padding`.
  final EdgeInsets safeArea;

  /// Parses the bridge payload; `null` when the channel answered nothing
  /// usable (non-iOS, hidden status bar, or a missing plugin).
  static Mv2SceneGeometry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final status = raw['statusBar'];
    final safe = raw['safeArea'];
    if (status is! Map || safe is! Map) return null;

    double read(Map<Object?, Object?> map, String key) {
      final value = map[key];
      return value is num ? value.toDouble() : 0;
    }

    final frame = Rect.fromLTWH(
      read(status, 'x'),
      read(status, 'y'),
      read(status, 'width'),
      read(status, 'height'),
    );
    if (frame.isEmpty) return null;
    return Mv2SceneGeometry(
      statusBarFrame: frame,
      safeArea: EdgeInsets.fromLTRB(
        read(safe, 'left'),
        read(safe, 'top'),
        read(safe, 'right'),
        read(safe, 'bottom'),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Mv2SceneGeometry &&
      other.statusBarFrame == statusBarFrame &&
      other.safeArea == safeArea;

  @override
  int get hashCode => Object.hash(statusBarFrame, safeArea);
}

/// Last geometry reported by iOS; `null` before the first sync and on every
/// non-iOS platform. Callers must degrade to `MediaQuery` when it is null.
Mv2SceneGeometry? mv2SceneGeometry;

/// ---------------------------------------------------------------------------
/// iPhone Duo control bar
///
/// Rules and numbers below are absorbed from `adaptive_platform_ui` (MIT),
/// which builds the native-looking Duo bar on top of `foldable`'s reserved
/// regions, then cross-checked against what this device reports. `foldable`
/// gives us, on the cover display:
///
///   occlusion Rect.fromLTRB(382.0,   0.0, 466.0, 170.0)   // status cluster
///   occlusion Rect.fromLTRB(399.7,  29.3, 436.7,  66.3)   // camera
///
/// The camera's centre is x = 418.2pt, which is also the centre of the band
/// ([mv2DuoBarBezelInset] inward from the strip) — that is the axis the system
/// draws its own controls on, so we lay ours out there too.
/// ---------------------------------------------------------------------------

/// Band = the system's strip plus this much *inward*, so the centred controls
/// sit a few points off the bezel instead of hugging the display edge.
const double mv2DuoBarBezelInset = 12.0;

/// Strip width to assume while the system reports no side inset.
const double mv2DuoBarFallbackStripWidth = 60.0;

/// Clearance kept below the top edge while the system has not yet reported
/// where its status cluster is; the cluster region is 170pt deep on the cover
/// display, so nothing starts out underneath it.
const double mv2DuoStatusClusterFallbackHeight = 170.0;

/// Space the system leaves between the controls and a free window edge.
const double mv2DuoBarEdgeMargin = 24.0;

/// Space the system leaves between the controls and a reserved region.
const double mv2DuoBarRegionGap = 11.0;

/// Liquid Glass capsule geometry: width, pitch between toolbar actions, tab
/// item height and the capsule's own inset.
const double mv2DuoCapsuleWidth = 48.0;
const double mv2DuoActionPitch = 52.0;
const double mv2DuoTabItemHeight = 50.0;
const double mv2DuoTabsInset = 6.0;

/// Height of a tab capsule holding [count] destinations.
double mv2DuoTabsHeight(int count) =>
    mv2DuoTabsInset * 2 + count * mv2DuoTabItemHeight;

/// The edge of the window the system reserves for its vertical controls.
enum Mv2DuoBarSide { left, right }

/// Which edge hosts the bar, or null where the system keeps horizontal bars.
///
/// Decided from what the system reserves rather than from a device or a width
/// breakpoint: no top inset plus a single side inset. That strip is on the
/// right on the inner display in one landscape rotation and on the cover
/// display in portrait, and on the *left* in the other rotation; every other
/// iPhone (top inset in portrait, symmetric sides in landscape) and iPad
/// (no side inset) keeps the floating bar.
Mv2DuoBarSide? mv2DuoBarSideOf(BuildContext context) {
  final padding = MediaQuery.viewPaddingOf(context);
  if (padding.top != 0) return null;
  if (padding.right > 0 && padding.left == 0) return Mv2DuoBarSide.right;
  if (padding.left > 0 && padding.right == 0) return Mv2DuoBarSide.left;
  return null;
}

/// Width of the strip the system reserves on [mv2DuoBarSideOf]'s edge.
double mv2DuoStripWidthOf(BuildContext context) {
  final padding = MediaQuery.viewPaddingOf(context);
  final side = mv2DuoBarSideOf(context);
  final inset = side == Mv2DuoBarSide.left ? padding.left : padding.right;
  return inset > 0 ? inset : mv2DuoBarFallbackStripWidth;
}

/// Width of the band the bar lays out in: strip plus [mv2DuoBarBezelInset].
double mv2DuoBandWidthOf(BuildContext context) =>
    mv2DuoStripWidthOf(context) + mv2DuoBarBezelInset;

/// Free space to keep above and below the controls so they clear the camera and
/// the status cluster wherever the current rotation puts them.
///
/// Only *occlusion* regions that really lie in this window's strip count: while
/// the device folds, unfolds or rotates, a reading taken in the previous pose
/// can still be around. Regions arrive a moment after launch and after a pose
/// change, so an empty strip means "not reported yet" and the fallback applies
/// rather than a control starting out underneath the cluster.
({double top, double bottom}) mv2DuoBarInsetsOf(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final strip = mv2DuoStripWidthOf(context);
  final left = mv2DuoBarSideOf(context) == Mv2DuoBarSide.left;
  final stripStart = left ? 0.0 : size.width - strip;
  final stripEnd = left ? strip : size.width;
  final regions =
      DuoMediaQuery.maybeOf(context)?.regions ?? const <ReservedRegion>[];

  final inStrip = regions.where(
    (ReservedRegion r) =>
        r.kind == ReservedRegionKind.occlusion &&
        r.isActive &&
        r.bounds.right > stripStart &&
        r.bounds.left < stripEnd &&
        r.bounds.right <= size.width + 1 &&
        r.bounds.bottom <= size.height + 1,
  );

  double? top;
  double? bottom;
  for (final ReservedRegion region in inStrip) {
    if (region.bounds.center.dy < size.height / 2) {
      if (top == null || region.bounds.bottom > top) top = region.bounds.bottom;
    } else {
      final room = size.height - region.bounds.top + mv2DuoBarRegionGap;
      if (bottom == null || room > bottom) bottom = room;
    }
  }

  final unknown = inStrip.isEmpty;
  return (
    top:
        top ??
        (unknown ? mv2DuoStatusClusterFallbackHeight : mv2DuoBarEdgeMargin),
    // The home indicator still has to stay clear on the cover display, where
    // the safe area is 34pt against this 24pt margin.
    bottom: math.max(
      bottom ?? mv2DuoBarEdgeMargin,
      MediaQuery.paddingOf(context).bottom,
    ),
  );
}

/// Width of the strip the system reserves for its own vertical chrome, or 0
/// when the window has none.
///
/// Both Duo states have it (folded cover display and unfolded inner display),
/// which is why this does **not** look at the width class. Sources, in order:
/// the window-chrome scope (the host already carved the strip out), the side
/// the system reserved ([mv2DuoBarSideOf], which also covers the rotation that
/// puts the strip on the *left*), then an engine-reported display feature
/// (Android foldables). Phones and iPads report none of these.
double mv2TrailingStripWidth(BuildContext context) {
  // Window chrome host wins: it already subtracted the strip from the content.
  final scope = Mv2WindowChromeScope.maybeOf(context);
  if (scope != null) return scope.stripWidth;
  // iPhone Duo: whatever edge the system reserved for its vertical bars.
  if (mv2DuoBarSideOf(context) != null) return mv2DuoStripWidthOf(context);
  // Android foldables do report display features; use them when present.
  final feature = mv2TrailingDisplayFeature(context);
  return feature?.bounds.width ?? 0;
}

DisplayFeature? mv2TrailingDisplayFeature(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  for (final feature in MediaQuery.displayFeaturesOf(context)) {
    final bounds = feature.bounds;
    // A full-height strip glued to the trailing edge.
    if (bounds.width < trailingRailMinInset) continue;
    if (bounds.height < size.height / 2) continue;
    if (bounds.right < size.width - 0.5) continue;
    return feature;
  }
  return null;
}

/// Whether the shell should host its chrome in a vertical trailing rail.
bool mv2UsesTrailingRail(BuildContext context) =>
    mv2TrailingStripWidth(context) > 0;

/// Vertical inset the chrome must keep clear so the system's own status cluster
/// (camera occlusion, clock and status items, stacked along that edge on the
/// Duo) is not covered by our controls.
///
/// Comes straight from the device: `foldable` reports the cluster as an
/// occlusion region up to 170pt deep, so this no longer relies on a measured
/// constant. See [mv2DuoBarInsetsOf] for the full rule and its fallbacks.
double mv2RailTopInset(BuildContext context, double stripWidth) {
  if (stripWidth <= 0) return MediaQuery.paddingOf(context).top;
  return mv2DuoBarInsetsOf(context).top;
}
