import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../../shared/models/models.dart';
import '../primitives/mv2_avatar.dart';

/// Card for one VXNA aggregator entry (`/xna`).
///
/// VXNA syndicates **external** articles, so the card deliberately differs from
/// [TopicItem]: a source-site badge replaces the node badge, there is no reply
/// count, and tapping opens the article in the browser instead of pushing an
/// in-app topic route.
class XnaItem extends StatelessWidget {
  const XnaItem({super.key, required this.entry, this.onTap});

  final V2XnaEntry entry;

  /// Overrides the default "open in browser" behaviour (used by tests).
  final VoidCallback? onTap;

  Future<void> _open(BuildContext context) async {
    if (onTap != null) {
      onTap!();
      return;
    }
    final uri = Uri.tryParse(entry.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final author = entry.author;

    return Mv2Surface(
      borderRadius: Mv2Radius.allMd,
      shadowed: false,
      onTap: () => _open(context),
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _SourceBadge(label: entry.sourceName),
              const Spacer(),
              if (entry.timeLabel?.isNotEmpty ?? false)
                Text(
                  entry.timeLabel!,
                  style: context.text.metadata.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Mv2Spacing.x2),
          Text(
            entry.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: context.text.topicTitle.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: Mv2Spacing.x3),
          Row(
            children: <Widget>[
              if (author != null) ...<Widget>[
                Mv2Avatar(user: author, size: 20),
                const SizedBox(width: Mv2Spacing.x2),
              ],
              Flexible(
                child: Text(
                  author == null
                      ? entry.sourceName
                      : '${author.username} · ${entry.sourceName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.metadata.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: Mv2Spacing.x2),
              Icon(
                Icons.open_in_new_rounded,
                size: 14,
                color: colors.textTertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Source-site label (`素生`, `愆伏`), the VXNA counterpart of a node badge.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: Mv2Radius.allXs,
      ),
      child: Text(
        label,
        style: context.text.badge.copyWith(color: colors.accent),
      ),
    );
  }
}
