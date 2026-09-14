import 'package:flutter/material.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_motion.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';

/// Compact circular icon button used in page headers and toolbars.
///
/// Keeps a ≥48px hit target even when the visual is 36–40px
/// (`docs/04-design-system.md` §9).
class Mv2IconButton extends StatelessWidget {
  const Mv2IconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 38,
    this.iconSize = 20,
    this.tooltip,
    this.filled = false,
    this.glass = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;

  /// Uses the surface fill + hairline border (e.g. header actions).
  final bool filled;

  /// Frosted variant for use over scrolling content.
  final bool glass;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = color ?? colors.textPrimary;

    final Widget visual = SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(icon, size: iconSize, color: fg),
      ),
    );

    final Widget surface = glass
        ? Mv2GlassSurface(
            borderRadius: Mv2Radius.pill,
            blur: 16,
            shadows: const <BoxShadow>[],
            child: visual,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: filled ? colors.surface : Colors.transparent,
              shape: BoxShape.circle,
              border: filled ? Border.all(color: colors.border) : null,
            ),
            child: visual,
          );

    return Semantics(
      button: true,
      label: tooltip,
      child: SizedBox(
        width: size < Mv2Spacing.minTapTarget ? Mv2Spacing.minTapTarget : size,
        height: size < Mv2Spacing.minTapTarget ? Mv2Spacing.minTapTarget : size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Center(child: surface),
        ),
      ),
    );
  }
}

/// Text button in the MV2 accent style (e.g. composer `发送`).
class Mv2TextButton extends StatelessWidget {
  const Mv2TextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.enabled = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = enabled && !loading && onPressed != null;
    final fg = active ? colors.accent : colors.textTertiary;

    return Semantics(
      button: true,
      enabled: active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active ? onPressed : null,
        child: AnimatedOpacity(
          duration: Mv2Motion.tap,
          opacity: active ? 1 : 0.6,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Mv2Spacing.x2,
              vertical: Mv2Spacing.x2,
            ),
            child: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  )
                : Text(label, style: context.text.button.copyWith(color: fg)),
          ),
        ),
      ),
    );
  }
}

/// Small action button used inside the composer toolbar
/// (`引用 / 预览 / 表情 / Markdown`).
class Mv2ToolbarButton extends StatelessWidget {
  const Mv2ToolbarButton({
    super.key,
    required this.label,
    this.icon,
    this.leadingText,
    this.onPressed,
    this.active = false,
  });

  final String label;
  final IconData? icon;

  /// Renders a text glyph instead of an icon (e.g. the `M` markdown mark).
  final String? leadingText;

  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = active ? colors.accent : colors.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x3,
          vertical: Mv2Spacing.x2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) Icon(icon, size: 17, color: fg),
            if (leadingText != null)
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: Mv2Radius.allXs,
                  border: Border.all(color: fg),
                ),
                child: Text(
                  leadingText!,
                  style: context.text.badge.copyWith(color: fg, fontSize: 11),
                ),
              ),
            if (icon != null || leadingText != null)
              const SizedBox(width: Mv2Spacing.x2),
            Text(label, style: context.text.bodySmall.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
