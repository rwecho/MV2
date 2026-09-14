import 'package:flutter/material.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../../shared/models/models.dart';
import '../primitives/mv2_avatar.dart';

/// Reply row for `designs/02-topic-detail.png`.
///
/// Flat row separated by hairlines — replies are never boxed into cards.
class ReplyItem extends StatelessWidget {
  const ReplyItem({
    super.key,
    required this.reply,
    this.onThank,
    this.onQuote,
    this.onLongPress,
  });

  final V2Reply reply;
  final VoidCallback? onThank;
  final VoidCallback? onQuote;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x4,
          vertical: Mv2Spacing.x4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Mv2Avatar(user: reply.author, size: 34),
            const SizedBox(width: Mv2Spacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          '@${reply.author.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyStrong.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: Mv2Spacing.x2),
                      Text(
                        '#${reply.floor} · ${reply.createdAtLabel}',
                        style: context.text.metadata.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Mv2Spacing.x2),
                  Text(
                    reply.content,
                    style: context.text.bodySmall.copyWith(
                      color: colors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: Mv2Spacing.x2),
                  Row(
                    children: <Widget>[
                      // V2EX has no reply like; 感谢 is the only reply feedback.
                      _ReplyAction(
                        icon: reply.thanked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: '感谢',
                        highlighted: reply.thanked,
                        onTap: onThank,
                      ),
                      if (onQuote != null) ...<Widget>[
                        const SizedBox(width: Mv2Spacing.x5),
                        _ReplyAction(
                          icon: Icons.format_quote_rounded,
                          label: '引用',
                          onTap: onQuote,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyAction extends StatelessWidget {
  const _ReplyAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = highlighted ? colors.accent : colors.textTertiary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 4),
          Text(label, style: context.text.metadata.copyWith(color: fg)),
        ],
      ),
    );
  }
}
