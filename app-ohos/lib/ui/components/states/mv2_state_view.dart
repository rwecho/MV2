import 'package:flutter/material.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';

/// The three failure/shortage states every list must implement
/// (`agent/AGENTS.md` rule 9). One component, no per-page ad-hoc variants.
enum Mv2StateKind { empty, error, offline }

class Mv2StateView extends StatelessWidget {
  const Mv2StateView({
    super.key,
    required this.kind,
    this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final Mv2StateKind kind;
  final String? title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Compact variant for inline (inside a card / below a header) placement.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (
      IconData icon,
      String defaultTitle,
      String defaultDescription,
    ) = switch (kind) {
      Mv2StateKind.empty => (Icons.inbox_outlined, '这里还没有内容', '换个条件看看，或者稍后再来。'),
      Mv2StateKind.error => (
        Icons.error_outline_rounded,
        '加载失败',
        '网络或服务暂时不可用，请重试。',
      ),
      Mv2StateKind.offline => (
        Icons.wifi_off_rounded,
        '当前离线',
        '已展示本地缓存内容，恢复网络后将自动刷新。',
      ),
    };

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x8,
          vertical: compact ? Mv2Spacing.x6 : Mv2Spacing.x10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.divider,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: colors.textTertiary),
            ),
            const SizedBox(height: Mv2Spacing.x4),
            Text(
              title ?? defaultTitle,
              textAlign: TextAlign.center,
              style: context.text.itemTitle.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: Mv2Spacing.x2),
            Text(
              description ?? defaultDescription,
              textAlign: TextAlign.center,
              style: context.text.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: Mv2Spacing.x5),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Mv2Spacing.x5,
                    vertical: Mv2Spacing.x3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: Mv2Radius.allSm,
                  ),
                  child: Text(
                    actionLabel!,
                    style: context.text.button.copyWith(
                      color: colors.accentContrast,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
