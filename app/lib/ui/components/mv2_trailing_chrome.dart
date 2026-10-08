import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_motion.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../../features/shell/application/chrome_actions.dart';
import '../utils/scene_geometry.dart';
import 'mv2_floating_tab_bar.dart';

/// The iPhone Duo's trailing edge chrome: **a toolbar on top of a tab bar**,
/// both inside the safe-area strip the device reserves along its sensor-bar
/// edge (folded cover display and unfolded inner display alike).
///
/// Apple's guidance for the device ("Designing for iPhone Duo") puts the system
/// status column, the app's toolbar and the app's tab bar in that one strip;
/// iOS draws the Dynamic Island and status items, we draw the other two:
///
/// * [_ToolbarSection] — the current page's actions. A topic contributes
///   收藏 / 感谢 / 分享 through [toolbarActionsProvider]; every other page falls
///   back to 搜索 / 账号.
/// * [_TabBarSection] — the five shell destinations.
///
/// [topInset] clears the system's own column (see `mv2RailTopInset` in
/// `ui/utils/scene_geometry.dart`, named for the strip, not for this widget).
/// Devices without such a strip keep [Mv2FloatingTabBar].
class Mv2TrailingChrome extends ConsumerWidget {
  const Mv2TrailingChrome({
    super.key,
    required this.current,
    required this.onSelect,
    this.notificationUnread = 0,
    this.topInset = 0,
    this.bottomInset = 0,
    this.stripWidth = duoStatusColumnWidth + 2 * duoStatusColumnLeading,
  });

  /// Currently selected shell destination.
  final Mv2Tab current;

  /// Same callback as the floating bar, so both chromes switch branches
  /// identically (haptics, attribution, chrome reset).
  final ValueChanged<Mv2Tab> onSelect;

  final int notificationUnread;

  /// Height the system's own status column occupies at the top of the strip.
  final double topInset;

  /// Safe-area inset at the bottom of the window.
  final double bottomInset;

  /// Width of the strip this chrome lives in, so its contents can sit on the
  /// system column's axis (see [mv2StripColumnInsets]).
  final double stripWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageActions =
        ref.watch(toolbarActionsProvider) ?? const <Mv2ToolbarAction>[];

    return Padding(
      // Clear the system chrome first.
      padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
      child: Padding(
        // Both sections sit on the *system* column's axis, not the strip's
        // centre: measured island/glyphs span 16..58pt of the 84pt strip.
        padding: mv2StripColumnInsets(stripWidth),
        child: Column(
          // Two distinct clusters, not one continuous bar (Apple's Duo mockups):
          // the tab bar is pinned to the bottom, the toolbar sits right below
          // the system's column and scrolls if a page offers more actions than
          // the strip's height can show at once.
          children: <Widget>[
            Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                child: _ToolbarSection(actions: pageActions),
              ),
            ),
            // Centred in the space left below the toolbar, the way Apple's
            // mockup floats this cluster instead of pinning it to the edge.
            Expanded(
              child: Center(
                child: _Cluster(
                  child: _TabBarSection(
                    current: current,
                    onSelect: onSelect,
                    notificationUnread: notificationUnread,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One frosted cluster of the strip: its own rounded glass panel and margin, so
/// the toolbar and the tab bar read as separate controls.
class _Cluster extends StatelessWidget {
  const _Cluster({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x2),
      child: Mv2GlassSurface(
        borderRadius: Mv2Radius.nav,
        blur: 20,
        padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x3),
        // Same width as the status column above and the toolbar buttons.
        child: SizedBox(width: duoStatusColumnWidth, child: child),
      ),
    );
  }
}

/// The strip's toolbar: a column of **separate circular buttons** — Apple's
/// shape for this edge (the tab bar below is a cluster, the toolbar is not).
///
/// Shows the current page's actions (收藏 / 感谢 / 分享 / ⋯ on a topic) or the
/// default 搜索 / 账号. `⋯` is reserved for overflow, per the HIG, and the page
/// publishes it like any other action.
class _ToolbarSection extends StatelessWidget {
  const _ToolbarSection({required this.actions});

  final List<Mv2ToolbarAction> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (actions.isEmpty) return const SizedBox.shrink();
    final shown = actions.take(maxToolbarActions);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final action in shown)
          _CircleAction(
            semanticsLabel: action.label,
            onTap: action.onTap,
            icon: Icon(
              action.active ? (action.activeIcon ?? action.icon) : action.icon,
              size: 20,
              color: action.active ? colors.accent : colors.textSecondary,
            ),
          ),
      ],
    );
  }
}

/// One circular toolbar button: its own glass disc, 44pt across.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  final Widget icon;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CircleSurface(
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: _circleSize,
            height: _circleSize,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

/// Frosted disc + the margin that keeps consecutive buttons apart.
class _CircleSurface extends StatelessWidget {
  const _CircleSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x1),
      child: Mv2GlassSurface(
        borderRadius: Mv2Radius.pill,
        blur: 20,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: _circleSize,
          height: _circleSize,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Toolbar button diameter: the system column's width, so a button lines up
/// with the status column above it.
const double _circleSize = duoStatusColumnWidth;

/// 发布 accent disc, kept inside the column width.
const double _publishSize = 28;

/// The strip's tab bar: the five shell destinations as icon tiles.
///
/// Apple's mockup for this edge shows icon-only tiles in a narrow cluster (the
/// labels of the phone bar do not fit an 42pt-wide column), with the selected
/// one on a filled rounded square, so that is what this renders.
class _TabBarSection extends StatelessWidget {
  const _TabBarSection({
    required this.current,
    required this.onSelect,
    required this.notificationUnread,
  });

  final Mv2Tab current;
  final ValueChanged<Mv2Tab> onSelect;
  final int notificationUnread;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final spec in mv2TabSpecs)
          if (spec.tab == Mv2Tab.publish)
            _TabBarPublish(onTap: () => onSelect(spec.tab))
          else
            _TabBarItem(
              spec: spec,
              selected: current == spec.tab,
              badgeCount: spec.tab == Mv2Tab.notifications
                  ? notificationUnread
                  : 0,
              onTap: () => onSelect(spec.tab),
            ),
      ],
    );
  }
}

/// One destination: a square icon tile, sized to the column.
class _TabBarItem extends StatelessWidget {
  const _TabBarItem({
    required this.spec,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final Mv2TabSpec spec;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? colors.accent : colors.textTertiary;

    return Semantics(
      button: true,
      selected: selected,
      label: spec.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: duoStatusColumnWidth,
          height: _tileSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Center(
                child: AnimatedContainer(
                  duration: Mv2Motion.tab,
                  width: _tileSize - 6,
                  height: _tileSize - 6,
                  decoration: BoxDecoration(
                    color: selected ? colors.accentSoft : Colors.transparent,
                    borderRadius: Mv2Radius.allMd,
                  ),
                  child: Icon(
                    selected ? spec.activeIcon : spec.icon,
                    size: 20,
                    color: fg,
                  ),
                ),
              ),
              if (badgeCount > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: _ChromeBadge(count: badgeCount),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Height of one destination tile in the strip.
const double _tileSize = 40;

class _TabBarPublish extends StatelessWidget {
  const _TabBarPublish({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: '发布',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: duoStatusColumnWidth,
          height: _tileSize,
          child: Center(
            child: Container(
              width: _publishSize,
              height: _publishSize,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_rounded,
                size: 18,
                color: colors.accentContrast,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChromeBadge extends StatelessWidget {
  const _ChromeBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      constraints: const BoxConstraints(minWidth: 15),
      decoration: BoxDecoration(
        color: colors.danger,
        borderRadius: Mv2Radius.pill,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: context.text.tabLabel.copyWith(
          color: Colors.white,
          fontSize: 10,
        ),
      ),
    );
  }
}
