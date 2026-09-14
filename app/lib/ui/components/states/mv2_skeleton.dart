import 'package:flutter/material.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_motion.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';

/// Shimmering placeholder block. Feed/topic lists must show skeletons rather
/// than a blocking spinner (`docs/07-component-specifications.md`).
class Mv2SkeletonBox extends StatefulWidget {
  const Mv2SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = Mv2Radius.allXs,
  });

  final double width;
  final double height;
  final BorderRadius radius;

  @override
  State<Mv2SkeletonBox> createState() => _Mv2SkeletonBoxState();
}

class _Mv2SkeletonBoxState extends State<Mv2SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Mv2Motion.shimmer,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.radius,
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t), 0),
              colors: <Color>[
                colors.shimmerBase,
                colors.shimmerHighlight,
                colors.shimmerBase,
              ],
              stops: const <double>[0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Feed-shaped skeleton matching [TopicItem] metrics.
class TopicItemSkeleton extends StatelessWidget {
  const TopicItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Mv2Radius.allMd,
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Mv2SkeletonBox(width: 36, height: 18),
              Spacer(),
              Mv2SkeletonBox(width: 48, height: 12),
            ],
          ),
          SizedBox(height: Mv2Spacing.x3),
          Mv2SkeletonBox(width: 240, height: 16),
          SizedBox(height: Mv2Spacing.x2),
          Mv2SkeletonBox(width: double.infinity, height: 12),
          SizedBox(height: Mv2Spacing.x1),
          Mv2SkeletonBox(width: 180, height: 12),
          SizedBox(height: Mv2Spacing.x3),
          Row(
            children: <Widget>[
              Mv2SkeletonBox(width: 20, height: 20, radius: Mv2Radius.pill),
              SizedBox(width: Mv2Spacing.x2),
              Mv2SkeletonBox(width: 96, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

/// A vertical list of feed skeletons.
class TopicListSkeleton extends StatelessWidget {
  const TopicListSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: Mv2Spacing.pageNarrow),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: Mv2Spacing.x3),
      itemBuilder: (_, _) => const TopicItemSkeleton(),
    );
  }
}
