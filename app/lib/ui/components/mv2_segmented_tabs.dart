import 'package:flutter/material.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_motion.dart';
import '../../design_system/tokens/mv2_spacing.dart';

/// MV2 segmented control (`主题 / 用户 / 节点`, `全部 / 回复 / @我`).
///
/// The home feed no longer uses this — its V2EX tab set needs a scrollable
/// row (`Mv2TabStrip`).
///
/// Self-built on purpose: the mockups use a flat track with a white active
/// capsule, which the Shad `Tabs` primitive does not produce
/// (`docs/05-shadcn-boundaries.md`).
class Mv2SegmentedTabs extends StatelessWidget {
  const Mv2SegmentedTabs({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.padded = false,
  });

  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// When true the control adds horizontal page padding and stretches.
  final bool padded;

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final track = Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.divider,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / items.length;
          return Stack(
            children: <Widget>[
              AnimatedAlign(
                duration: Mv2Motion.tab,
                curve: Mv2Motion.standard,
                alignment: Alignment(
                  items.length == 1
                      ? 0
                      : (selectedIndex / (items.length - 1)) * 2 - 1,
                  0,
                ),
                child: Container(
                  width: segmentWidth,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: const BorderRadius.all(Radius.circular(11)),
                    boxShadow: colors.brightness == Brightness.light
                        ? const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x0F0F172A),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _Segment(
                        label: items[i],
                        selected: i == selectedIndex,
                        onTap: () => onChanged(i),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );

    if (!padded) return track;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Mv2Spacing.pageNarrow),
      child: track,
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: Mv2Motion.tab,
          style: context.text.bodySmall.copyWith(
            color: selected ? colors.accent : colors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
