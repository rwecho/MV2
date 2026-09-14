import 'package:flutter/material.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_motion.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';

/// Horizontally scrollable text tab row used for the home feed's V2EX tab set
/// (`技术 创意 好玩 Apple … VXNA`).
///
/// V2EX renders its home tabs as a scrollable row with the current one
/// highlighted; the MV2 take keeps that behaviour but styles the active state
/// with the accent colour plus an underline (the previous fixed 4-segment
/// control cannot hold ~12 tabs). The selected tab is scrolled into view, so a
/// restored selection is visible on launch.
class Mv2TabStrip extends StatefulWidget {
  const Mv2TabStrip({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// Row height including the underline track.
  static const double height = 42;

  @override
  State<Mv2TabStrip> createState() => _Mv2TabStripState();
}

class _Mv2TabStripState extends State<Mv2TabStrip> {
  final ScrollController _controller = ScrollController();
  late List<GlobalKey> _keys = _buildKeys();

  List<GlobalKey> _buildKeys() =>
      List<GlobalKey>.generate(widget.labels.length, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    // A persisted selection may sit off-screen; reveal it once laid out.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealSelected(animate: false),
    );
  }

  @override
  void didUpdateWidget(Mv2TabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.labels.length != widget.labels.length) {
      _keys = _buildKeys();
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _revealSelected({bool animate = true}) {
    if (!mounted) return;
    final index = widget.selectedIndex;
    if (index < 0 || index >= _keys.length) return;
    final context = _keys[index].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: animate ? Mv2Motion.tab : Duration.zero,
      curve: Mv2Motion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: Mv2TabStrip.height,
      child: Stack(
        children: <Widget>[
          ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: Mv2Spacing.pageNarrow,
            ),
            itemCount: widget.labels.length,
            itemBuilder: (context, index) => _Tab(
              key: _keys[index],
              label: widget.labels[index],
              selected: index == widget.selectedIndex,
              onTap: () => widget.onChanged(index),
            ),
          ),
          // Hairline the underlines sit on, matching the tab-row baseline.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(height: 1, color: colors.divider),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Mv2Spacing.x3),
        // The horizontal ListView hands each item unbounded width, so the
        // stretch column needs an intrinsic width to size its children (and
        // the full-label underline) against.
        child: IntrinsicWidth(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                label,
                textAlign: TextAlign.center,
                style: context.text.bodySmall.copyWith(
                  color: selected ? colors.accent : colors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: Mv2Spacing.x1),
              AnimatedContainer(
                duration: Mv2Motion.tab,
                curve: Mv2Motion.standard,
                height: 2,
                decoration: BoxDecoration(
                  color: selected ? colors.accent : Colors.transparent,
                  borderRadius: Mv2Radius.pill,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
