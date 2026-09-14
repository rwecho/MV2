import 'package:flutter/material.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';

/// Bottom reply affordance on the topic detail page
/// (`designs/02-topic-detail.png`).
///
/// Frosted bar + placeholder + accent send button; tapping the field opens the
/// composer instead of typing in place.
class FloatingReplyBar extends StatelessWidget {
  const FloatingReplyBar({
    super.key,
    this.placeholder = '写下你的回复...',
    this.onTap,
    this.onSend,
    this.enabled = true,
  });

  final String placeholder;
  final VoidCallback? onTap;
  final VoidCallback? onSend;
  final bool enabled;

  static const double height = 54;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: Mv2Spacing.pageNarrow,
        right: Mv2Spacing.pageNarrow,
        bottom: bottomInset > 0 ? bottomInset : Mv2Spacing.x2,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: Mv2Spacing.maxContentWidth,
          ),
          child: Mv2GlassSurface(
            borderRadius: Mv2Radius.pill,
            blur: 20,
            child: SizedBox(
              height: height,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: Mv2Spacing.x4),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: enabled ? onTap : null,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          placeholder,
                          style: context.text.bodySmall.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: Mv2Spacing.x2),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: enabled ? onSend : null,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: enabled ? colors.accent : colors.divider,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          size: 18,
                          color: enabled
                              ? colors.accentContrast
                              : colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
