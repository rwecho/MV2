import 'package:flutter/material.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../../shared/format/mv2_format.dart';
import '../../shared/models/models.dart';
import '../primitives/mv2_chips.dart';

/// Node card for `designs/04-nodes-explore.png`.
///
/// Identity-first: tile, name, topic count, description, tags.
class NodeCard extends StatelessWidget {
  const NodeCard({super.key, required this.node, this.onTap});

  final V2Node node;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Mv2Surface(
      borderRadius: Mv2Radius.allMd,
      shadowed: false,
      onTap: onTap,
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Mv2NodeTile(node: node, size: 44),
          const SizedBox(width: Mv2Spacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.itemTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (node.topicCount != null)
                      Text(
                        '${Mv2Format.compactCount(node.topicCount!)} 主题',
                        style: context.text.metadata.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    // The chevron promises navigation, so only draw it when the
                    // card is actually tappable.
                    if (onTap != null) ...<Widget>[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.textTertiary,
                      ),
                    ],
                  ],
                ),
                if (node.description != null) ...<Widget>[
                  const SizedBox(height: Mv2Spacing.x1),
                  Text(
                    node.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall.copyWith(
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
                if (node.tags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Mv2Spacing.x2),
                  Wrap(
                    spacing: Mv2Spacing.x2,
                    runSpacing: Mv2Spacing.x1,
                    children: <Widget>[
                      for (final tag in node.tags) Mv2TagChip(label: tag),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
