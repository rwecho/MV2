import 'package:flutter/material.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_spacing.dart';

/// Clamps [child] to [collapsedHeight] and offers 展开全文 / 收起.
///
/// Used for long replies when 设置 → 自动折叠长回复 is on. Collapsing is a visual
/// clamp, not a rebuild: the child keeps its natural layout inside an
/// [OverflowBox], so rich text with images measures exactly as it normally does
/// and no overflow error is raised.
class Mv2CollapsibleBody extends StatefulWidget {
  const Mv2CollapsibleBody({
    super.key,
    required this.child,
    this.collapsedHeight = 128,
    this.expandLabel = '展开全文',
    this.collapseLabel = '收起',
  });

  final Widget child;

  /// Visible height while collapsed (~6 lines of `readingSmall`).
  final double collapsedHeight;

  final String expandLabel;
  final String collapseLabel;

  @override
  State<Mv2CollapsibleBody> createState() => _Mv2CollapsibleBodyState();
}

class _Mv2CollapsibleBodyState extends State<Mv2CollapsibleBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_expanded)
          widget.child
        else
          SizedBox(
            height: widget.collapsedHeight,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: widget.child,
              ),
            ),
          ),
        const SizedBox(height: Mv2Spacing.x1),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          // 整行都是热区：文字本身很小（metadata 字号），只给文字做点击
          // 目标太难点（用户反馈）。加纵向 padding 让热区高度接近 44px。
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x2),
              child: Text(
                _expanded ? widget.collapseLabel : widget.expandLabel,
                style: context.text.metadata.copyWith(
                  color: context.colors.accent,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
