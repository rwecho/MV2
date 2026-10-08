import 'package:flutter/widgets.dart';

/// Geometry iOS reports for the window, bridged from UIKit.
///
/// The Duo's own strip, fold and camera geometry come from `foldable` now
/// (`DuoMediaQuery`), and the fixed toolbar chrome from `adaptive_platform_ui`
/// places itself from those readings — so nothing here has to guess where the
/// system's chrome is. What is left is what the native bridge reports for the
/// scene itself, which the size-class sync keeps in step.
class Mv2SceneGeometry {
  const Mv2SceneGeometry({
    required this.statusBarFrame,
    required this.safeArea,
  });

  /// Where the system draws the status bar, in scene (logical) coordinates.
  /// Empty when hidden.
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
