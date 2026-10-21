import 'package:flutter/material.dart';

import '../../../design_system/theme/mv2_theme.dart';
import 'mv2_video_embed.dart';
import 'mv2_video_player_page.dart';

/// Resolves the provider player immediately; playback remains user initiated.
class Mv2VideoEmbedCard extends StatefulWidget {
  const Mv2VideoEmbedCard({super.key, required this.embed, this.anchorText});
  final Mv2VideoEmbed embed;
  final String? anchorText;

  @override
  State<Mv2VideoEmbedCard> createState() => _Mv2VideoEmbedCardState();
}

class _Mv2VideoEmbedCardState extends State<Mv2VideoEmbedCard> {
  bool _fullscreen = false;

  @override
  Widget build(BuildContext context) {
    final label =
        const {
          'hub': 'exe-hub',
          'bilibili': '哔哩哔哩',
          'youtube': 'YouTube',
        }[widget.embed.provider] ??
        '视频';
    final title = widget.anchorText?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _fullscreen
                ? const ColoredBox(color: Colors.black)
                : Mv2VideoSurface(
                    key: ValueKey(widget.embed.originalUrl),
                    embed: widget.embed,
                  ),
          ),
          ColoredBox(
            color: context.colors.accentSoft,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title != null &&
                              title.isNotEmpty &&
                              title != widget.embed.originalUrl
                          ? title
                          : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.metadata.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '打开全屏播放器',
                    icon: const Icon(Icons.fullscreen_rounded),
                    onPressed: () async {
                      setState(() => _fullscreen = true);
                      try {
                        await showMv2VideoPlayer(context, widget.embed);
                      } finally {
                        if (mounted) setState(() => _fullscreen = false);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
