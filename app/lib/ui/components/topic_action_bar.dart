import 'package:flutter/material.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';

/// `收藏 / 感谢 / 分享` bar that closes the topic body
/// (`designs/02-topic-detail.png`).
class TopicActionBar extends StatelessWidget {
  const TopicActionBar({
    super.key,
    this.favorited = false,
    this.thanked = false,
    this.thankCount = 0,
    this.onFavorite,
    this.onThank,
    this.onShare,
  });

  final bool favorited;
  final bool thanked;
  final int thankCount;
  final VoidCallback? onFavorite;
  final VoidCallback? onThank;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Mv2Surface(
      borderRadius: Mv2Radius.allMd,
      shadowed: false,
      child: SizedBox(
        height: 52,
        child: Row(
          children: <Widget>[
            _Action(
              icon: favorited ? Icons.star_rounded : Icons.star_border_rounded,
              label: '收藏',
              highlighted: favorited,
              onTap: onFavorite,
            ),
            _Divider(color: colors.divider),
            _Action(
              // `thanked` reflects the optimistic/server state: without it the
              // tap registered server-side but the bar never changed.
              icon: thanked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: thanked
                  ? '已感谢'
                  : (thankCount > 0 ? '感谢 $thankCount' : '感谢'),
              highlighted: thanked,
              onTap: onThank,
            ),
            _Divider(color: colors.divider),
            _Action(
              icon: Icons.ios_share_rounded,
              iconSize: 18,
              label: '分享',
              onTap: onShare,
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 20, color: color);
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    this.onTap,
    this.highlighted = false,
    this.iconSize = 19,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = highlighted ? colors.accent : colors.textSecondary;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: iconSize, color: fg),
            const SizedBox(width: Mv2Spacing.x2),
            Text(label, style: context.text.bodySmall.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
