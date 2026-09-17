import 'package:flutter/material.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_colors.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../../shared/models/models.dart';

/// Small node label shown at the top of a feed card (`AI`, `程序员`, `.NET`).
///
/// [onTap] turns the label into its own tap target — the topic rows use it to
/// open the node's topic stream (`/node/:key`) instead of the topic the card
/// points at. Without it the label stays inert (e.g. the reply composer, where
/// it only states where the reply will be posted).
class Mv2NodeBadge extends StatelessWidget {
  const Mv2NodeBadge({super.key, required this.node, this.onTap});

  final V2Node node;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: Mv2Radius.allXs,
      ),
      child: Text(
        node.name,
        style: context.text.badge.copyWith(color: colors.accent),
      ),
    );

    if (onTap == null) return badge;

    // Opaque so the tap stops here instead of bubbling up to the enclosing
    // card's own `onTap` (same trick as the author block in `TopicItem`).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: badge,
    );
  }
}

/// Interactive / static pill used by recent-node rows, recent searches and
/// sort filters.
class Mv2Chip extends StatelessWidget {
  const Mv2Chip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = selected ? colors.accentSoft : colors.surface;
    final fg = selected ? colors.accent : colors.textSecondary;
    final border = selected
        ? colors.accent.withValues(alpha: 0.35)
        : colors.border;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: dense ? 13 : 15, color: fg),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: (dense ? context.text.metadata : context.text.bodySmall)
              .copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
        ),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? Mv2Spacing.x3 : Mv2Spacing.x3,
          vertical: dense ? 6 : Mv2Spacing.x2,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: Mv2Radius.pill,
          border: Border.all(color: border),
        ),
        child: content,
      ),
    );
  }
}

/// Tag inside a node card (`编程`, `技术栈`, `职业发展`) — flat, no border.
class Mv2TagChip extends StatelessWidget {
  const Mv2TagChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Mv2Spacing.x2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colors.divider,
        borderRadius: Mv2Radius.allXs,
      ),
      child: Text(
        label,
        style: context.text.metadata.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

/// Group label above a settings / profile card (`内容`, `外观`, `关于`).
class Mv2SectionBadge extends StatelessWidget {
  const Mv2SectionBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x2,
          vertical: 3,
        ),
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

/// Rounded-square node identity tile (saturated fill + white glyph), matching
/// `designs/04-nodes-explore.png`.
class Mv2NodeTile extends StatelessWidget {
  const Mv2NodeTile({super.key, required this.node, this.size = 44});

  final V2Node node;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fill = Mv2NodePalette.fillFor(node.key);
    final soft = node.iconStyle == NodeIconStyle.soft;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: soft
            ? fill.withValues(alpha: context.isDarkMode ? 0.24 : 0.12)
            : fill,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Center(
        child: Icon(
          node.icon,
          size: size * 0.5,
          color: soft ? fill : Colors.white,
        ),
      ),
    );
  }
}
