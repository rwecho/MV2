import 'package:flutter/material.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';

/// Leading icon + label (+ optional description) + trailing value / control.
///
/// Used by `designs/07-profile-my.png` and `designs/08-settings.png`.
class Mv2SettingsRow extends StatelessWidget {
  const Mv2SettingsRow({
    super.key,
    required this.label,
    this.icon,
    this.leadingText,
    this.description,
    this.value,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.showDivider = true,
  });

  final String label;
  final IconData? icon;

  /// Text glyph used instead of an icon (e.g. `AA` for 字体大小, matching
  /// `designs/08-settings.png`).
  final String? leadingText;
  final String? description;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: colors.divider))
              : null,
        ),
        padding: EdgeInsets.fromLTRB(
          Mv2Spacing.x4,
          description != null ? Mv2Spacing.x3 : 0,
          Mv2Spacing.x4,
          description != null ? Mv2Spacing.x3 : 0,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 20, color: colors.textPrimary),
                const SizedBox(width: Mv2Spacing.x3),
              ] else if (leadingText != null) ...<Widget>[
                SizedBox(
                  width: 24,
                  child: Text(
                    leadingText!,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: context.text.itemTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: Mv2Spacing.x2),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      style: context.text.itemTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (description != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: context.text.metadata.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...<Widget>[
                const SizedBox(width: Mv2Spacing.x2),
                Text(
                  value!,
                  style: context.text.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
              if (trailing != null) ...<Widget>[
                const SizedBox(width: Mv2Spacing.x2),
                trailing!,
              ],
              if (showChevron) ...<Widget>[
                const SizedBox(width: Mv2Spacing.x1),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colors.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Card that groups [Mv2SettingsRow]s, with a section badge above it.
class Mv2SettingsGroup extends StatelessWidget {
  const Mv2SettingsGroup({
    super.key,
    this.badge,
    required this.children,
    this.topGap = Mv2Spacing.x5,
  });

  final String? badge;
  final List<Widget> children;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
    }

    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (badge != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(
                left: Mv2Spacing.x1,
                bottom: Mv2Spacing.x2,
              ),
              child: _Badge(label: badge!),
            ),
          ],
          Mv2Surface(
            borderRadius: Mv2Radius.allMd,
            shadowed: false,
            child: ClipRRect(
              borderRadius: Mv2Radius.allMd,
              child: Column(children: rows),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colors.accentSoft,
          borderRadius: Mv2Radius.allXs,
        ),
        child: Text(
          label,
          style: context.text.badge.copyWith(color: colors.accent),
        ),
      ),
    );
  }
}
