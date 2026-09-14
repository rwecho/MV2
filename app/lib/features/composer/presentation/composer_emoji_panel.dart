import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/emoji/mv2_emoji_library.dart';
import '../../../ui/primitives/mv2_chips.dart';

/// Inline emoji picker backed by V2EX Polish's library
/// (`shared/emoji/mv2_emoji_library.dart`).
///
/// Rendered above the composer toolbar instead of another sheet, so the draft
/// stays visible while picking. The 流行 group shows the hosted preview images;
/// every group inserts its [Mv2Emoji.token] at the caret.
class ComposerEmojiPanel extends StatefulWidget {
  const ComposerEmojiPanel({super.key, required this.onSelect});

  /// Receives the token to insert (`[doge]` or a Unicode glyph).
  final ValueChanged<String> onSelect;

  /// Panel height when pinned above the toolbar.
  static const double height = 232;

  @override
  State<ComposerEmojiPanel> createState() => _ComposerEmojiPanelState();
}

class _ComposerEmojiPanelState extends State<ComposerEmojiPanel> {
  int _groupIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final group = Mv2EmojiLibrary.groups[_groupIndex];

    return ColoredBox(
      color: colors.background,
      child: SizedBox(
        height: ComposerEmojiPanel.height,
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: Mv2Spacing.x3,
                  vertical: Mv2Spacing.x1,
                ),
                itemCount: Mv2EmojiLibrary.groups.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: Mv2Spacing.x2),
                itemBuilder: (context, index) => Mv2Chip(
                  label: Mv2EmojiLibrary.groups[index].title,
                  dense: true,
                  selected: index == _groupIndex,
                  onTap: () => setState(() => _groupIndex = index),
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  Mv2Spacing.x3,
                  Mv2Spacing.x2,
                  Mv2Spacing.x3,
                  Mv2Spacing.x3,
                ),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                      mainAxisSpacing: Mv2Spacing.x2,
                      crossAxisSpacing: Mv2Spacing.x2,
                    ),
                itemCount: group.emoji.length,
                itemBuilder: (context, index) {
                  final emoji = group.emoji[index];
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onSelect(emoji.token),
                    child: Center(child: _EmojiGlyph(emoji: emoji)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiGlyph extends StatelessWidget {
  const _EmojiGlyph({required this.emoji});

  final Mv2Emoji emoji;

  @override
  Widget build(BuildContext context) {
    final imageUrl = emoji.imageUrl;
    if (imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        width: 30,
        height: 30,
        fit: BoxFit.contain,
        placeholder: (_, _) => const SizedBox(width: 30, height: 30),
        errorWidget: (_, _, _) => Text(
          emoji.token,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: context.text.badge.copyWith(color: context.colors.textTertiary),
        ),
      );
    }
    return Text(emoji.token, style: const TextStyle(fontSize: 24, height: 1.1));
  }
}
