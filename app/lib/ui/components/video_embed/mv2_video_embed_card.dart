import 'package:flutter/material.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import 'mv2_video_embed.dart';
import 'mv2_video_player_page.dart';

/// Block-level video card rendered in place of a recognized video link
/// (`exe-hub` Post / Bilibili / YouTube) inside `Mv2RichText`.
///
/// The card is the tap target: tapping opens the in-app player page. Playback
/// is always in-app regardless of 设置 → 外链打开方式 — a video link opened in
/// the reader mode would just strip the player.
class Mv2VideoEmbedCard extends StatelessWidget {
  const Mv2VideoEmbedCard({super.key, required this.embed, this.anchorText});

  final Mv2VideoEmbed embed;

  /// The anchor's own text. When the author wrote `[标题](链接)` this is a real
  /// title; a bare pasted URL yields the URL itself, which reads better as the
  /// provider name + host line instead.
  final String? anchorText;

  static const Map<String, String> _providerLabels = <String, String>{
    'hub': 'exe-hub',
    'bilibili': '哔哩哔哩',
    'youtube': 'YouTube',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = _providerLabels[embed.provider] ?? embed.provider;
    final text = anchorText?.trim() ?? '';
    final titled = text.isNotEmpty && text != embed.originalUrl;

    return Semantics(
      button: true,
      label: '播放视频：$label',
      child: Mv2Surface(
        borderRadius: Mv2Radius.allMd,
        shadowed: false,
        onTap: () {
          Mv2Analytics.logVideoOpen(provider: embed.provider);
          showMv2VideoPlayer(context, embed);
        },
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x3,
          vertical: Mv2Spacing.x3,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: Mv2Radius.allSm,
              ),
              child: Icon(Icons.play_arrow_rounded, size: 24, color: colors.accent),
            ),
            const SizedBox(width: Mv2Spacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    titled ? text : '播放视频',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.itemTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Mv2Spacing.x1),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.metadata.copyWith(
                      color: colors.textTertiary,
                    ),
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
