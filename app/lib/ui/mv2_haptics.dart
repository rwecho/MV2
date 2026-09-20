import 'package:flutter/services.dart';

/// Haptic feedback helpers that honour 设置 → 触觉反馈.
///
/// The toggle is passed in rather than read here: call sites already hold a
/// `WidgetRef`, and resolving the preference at the moment of the gesture keeps
/// a mid-session toggle effective without rebuilding every widget.
abstract final class Mv2Haptics {
  /// Discrete toggle feedback: 感谢 / 收藏 / 忽略 / 切 tab.
  static void tap(bool enabled) {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  /// Stronger confirmation: a write succeeded. Deliberately a step above
  /// [tap] — `lightImpact` is near-imperceptible on many Android devices, and
  /// the whole point is that the user *felt* the 感谢 land.
  static void success(bool enabled) {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }
}
