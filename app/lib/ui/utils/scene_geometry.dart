import 'dart:math' as math;
import 'dart:ui' show DisplayFeature;

import 'package:flutter/widgets.dart';

/// Trailing safe-area strip (logical px) from which on the window clearly
/// reserves the iPhone Duo's sensor-bar edge.
///
/// Measured on both Duo states (folded cover display 466×678 and unfolded inner
/// display 951×669): trailing inset 84pt while the leading inset is 0. Phones
/// report symmetric insets in landscape (or a top-only inset in portrait), so
/// they never reach the threshold.
const double trailingRailMinInset = 60.0;

/// Height the Duo's system hardware covers at the top of the trailing strip,
/// used until the platform reports the reserved region itself.
///
/// Measured from the system's own drawing inside the strip, per state:
///
/// * unfolded inner display: clock glyphs at y 34..46pt and status icons at
///   57..88pt, island above them → 96pt cleared it;
/// * folded cover display: a solid black system/hardware block (the island /
///   sensor area, 46×60pt) spans y 84..144pt, so the same clearance put our
///   search icon (116..138pt) underneath it.
///
/// 160pt covers both states with a small margin.
///
/// Fallback only: a `DisplayFeatureType.cutout` from the engine
/// (flutter/flutter#193025) or a usable `statusBarFrame` wins when present.
const double duoStatusColumnInset = 160.0;

/// The window-scene geometry iOS reports (`mv2/native` → `uiGeometry`).
@immutable
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

/// Width of the trailing sensor-bar strip, or 0 when the window has none.
///
/// Both Duo states have it (folded cover display and unfolded inner display),
/// which is why this does **not** look at the width class: the strip is the
/// signal, and it is what the system reserves for its own chrome on that edge.
///
/// The engine-reported display feature wins when present (see
/// [mv2TrailingDisplayFeature]); otherwise the safe-area inset decides, with the
/// asymmetry test that keeps phones out.
double mv2TrailingStripWidth(BuildContext context) {
  final feature = mv2TrailingDisplayFeature(context);
  if (feature != null) return feature.bounds.width;
  final padding = MediaQuery.paddingOf(context);
  if (padding.right < trailingRailMinInset) return 0;
  if (padding.right <= padding.left) return 0;
  return padding.right;
}

/// The engine-reported reserved strip hugging the trailing edge, if any.
///
/// Flutter's channel for this is `MediaQuery.displayFeaturesOf` — the engine is
/// meant to describe the Duo's reserved edge region as a `cutout`/`hinge`
/// (flutter/flutter#193025). The engine in Flutter 3.47.3 reports an empty list
/// on the Duo, so this returns `null` today and the safe-area fallback applies;
/// once the engine populates it, the same call site picks up the official
/// bounds with no further change.
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

/// Vertical inset the rail must keep clear so the system's own status column
/// (Dynamic Island + status items, stacked along the trailing edge on the Duo)
/// is not covered by our controls.
///
/// Prefers an engine-reported obstruction that sits inside the strip and hugs
/// the top; otherwise falls back to [duoStatusColumnInset], which was measured
/// from the system's own drawing in that strip, and never goes below the media
/// padding. (`UIStatusBarManager.statusBarFrame` is consulted too, but on the
/// Duo it reports only ~2pt, so the measurement is what carries the layout.)
double mv2RailTopInset(BuildContext context, double stripWidth) {
  final mediaTop = MediaQuery.paddingOf(context).top;
  if (stripWidth <= 0) return mediaTop;

  final size = MediaQuery.sizeOf(context);
  for (final feature in MediaQuery.displayFeaturesOf(context)) {
    final bounds = feature.bounds;
    final inStrip =
        bounds.right >= size.width - 0.5 &&
        bounds.width >= trailingRailMinInset;
    // A partial-height obstruction at the very top of the strip is the island /
    // status area — our controls start below it.
    if (inStrip && bounds.top <= 0.5 && bounds.height < size.height / 2) {
      return math.max(mediaTop, bounds.bottom);
    }
  }

  var inset = math.max(mediaTop, duoStatusColumnInset);
  final geometry = mv2SceneGeometry;
  if (geometry != null) {
    final frame = geometry.statusBarFrame;
    // Only trust the frame when the system really draws that bar inside (or up
    // to) our strip; a status bar that stops well before it is a different
    // layout. (On the Duo it reports ~2pt, hence the measured floor above.)
    if (frame.right >= size.width - stripWidth - 1) {
      inset = math.max(inset, frame.bottom);
    }
  }
  return inset;
}
