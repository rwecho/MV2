import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/imgur_uploader.dart';
import '../../../core/telemetry/mv2_analytics.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../application/image_picker_gateway.dart';
import '../application/image_picker_providers.dart';

/// Toolbar action: pick a photo, host it on Imgur, insert it into the draft.
///
/// V2EX has no image host of its own; the returned link is inserted as
/// `![](https://i.imgur.com/…)` at the caret so the post renders the image.
class ComposerImageButton extends ConsumerStatefulWidget {
  const ComposerImageButton({super.key, required this.onInsert});

  /// Receives the Markdown snippet to insert at the caret.
  final ValueChanged<String> onInsert;

  @override
  ConsumerState<ComposerImageButton> createState() =>
      _ComposerImageButtonState();
}

class _ComposerImageButtonState extends ConsumerState<ComposerImageButton> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    // Platform-agnostic: the mainline provider wraps `image_picker`, the
    // HarmonyOS variant wraps the `mv2/image_picker` platform channel.
    final Mv2PickedImage? picked;
    try {
      picked = await ref.read(imagePickerProvider).pickImage();
    } catch (error) {
      // A picker that fails to open/hand back a readable file (the ohos bridge
      // answers `copy-failed` on a broken media URI) must not take down the
      // composer.
      if (!mounted) return;
      mv2ShowError(context, error);
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final url = await ref
          .read(imgurUploaderProvider)
          .upload(picked.bytes, filename: picked.filename);
      Mv2Analytics.logImageUpload(
        result: 'success',
        sizeBytes: picked.bytes.length,
      );
      if (!mounted) return;
      widget.onInsert('![]($url)');
    } catch (error) {
      Mv2Analytics.logImageUpload(
        result: 'failed',
        sizeBytes: picked.bytes.length,
      );
      if (!mounted) return;
      mv2ShowError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uploading) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x3,
          vertical: Mv2Spacing.x2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: Mv2Spacing.x2),
            Text(
              '上传中…',
              style: context.text.bodySmall.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return Mv2ToolbarButton(
      label: '图片',
      icon: Icons.image_outlined,
      onPressed: _pickAndUpload,
    );
  }
}
