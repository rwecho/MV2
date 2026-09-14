import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../../shared/models/models.dart';
import '../primitives/mv2_avatar.dart';
import '../primitives/mv2_chips.dart';

/// Topic row used by Home feed, node feed and search results.
///
/// Layout follows `designs/01-home-feed.png`: node badge + relative time,
/// 2-line title, 2-line excerpt, then author row with reply count.
///
/// This is an MV2 product component — never replace it with a Shad `Card`
/// (`docs/07-component-specifications.md`).
class TopicItem extends StatelessWidget {
  const TopicItem({
    super.key,
    required this.topic,
    this.onTap,
    this.showExcerpt = true,
    this.showNodeBadge = true,
  });

  final V2Topic topic;
  final VoidCallback? onTap;
  final bool showExcerpt;
  final bool showNodeBadge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final authorName = topic.author.username;
    final canOpenAuthor = authorName.isNotEmpty && authorName != '匿名';

    return Mv2Surface(
      borderRadius: Mv2Radius.allMd,
      shadowed: false,
      onTap: onTap,
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (showNodeBadge) Mv2NodeBadge(node: topic.node),
              if (topic.isPinned) ...<Widget>[
                const SizedBox(width: Mv2Spacing.x2),
                _PinnedBadge(),
              ],
              const Spacer(),
              if (!topic.isPinned && topic.createdAtLabel.isNotEmpty)
                Text(
                  topic.createdAtLabel,
                  style: context.text.metadata.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Mv2Spacing.x2),
          Text(
            topic.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.topicTitle.copyWith(
              color: topic.isRead ? colors.textSecondary : colors.textPrimary,
            ),
          ),
          if (showExcerpt && (topic.excerpt?.isNotEmpty ?? false)) ...<Widget>[
            const SizedBox(height: Mv2Spacing.x2),
            Text(
              topic.excerpt!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: Mv2Spacing.x3),
          Row(
            children: <Widget>[
              // The author block is its own tap target so a tap reaches the
              // member page instead of the card's own `onTap`; the opaque
              // behaviour keeps the card from swallowing it.
              Flexible(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canOpenAuthor
                      ? () => context.push('/member/$authorName')
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Mv2Avatar(user: topic.author, size: 20),
                      const SizedBox(width: Mv2Spacing.x2),
                      Flexible(
                        child: Text(
                          // Pinned rows carry no relative time, so `置顶` is
                          // rendered as a badge above instead of being repeated
                          // here.
                          topic.isPinned || topic.createdAtLabel.isEmpty
                              ? authorName
                              : '$authorName · ${topic.createdAtLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.metadata.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Mv2Spacing.x2),
              Icon(
                Icons.mode_comment_outlined,
                size: 14,
                color: colors.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                '${topic.replyCount}',
                style: context.text.metadata.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Marks a pinned topic (`置顶`) without stealing the relative-time slot.
class _PinnedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.divider,
        borderRadius: Mv2Radius.allXs,
      ),
      child: Text(
        '置顶',
        style: context.text.badge.copyWith(color: colors.textSecondary),
      ),
    );
  }
}
