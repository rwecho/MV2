import 'package:flutter/animation.dart';

/// MV2 motion tokens (`docs/04-design-system.md` §8).
///
/// No looping glow, no exaggerated bounce, no decorative rotation.
abstract final class Mv2Motion {
  static const Duration tap = Duration(milliseconds: 120);
  static const Duration tab = Duration(milliseconds: 180);
  static const Duration sheet = Duration(milliseconds: 260);

  /// Skeleton shimmer cycle.
  static const Duration shimmer = Duration(milliseconds: 1200);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
}
