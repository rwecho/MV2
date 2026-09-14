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

  /// Slightly stronger confirmation: a write succeeded.
  static void success(bool enabled) {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }
}
