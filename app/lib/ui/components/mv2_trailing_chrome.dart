import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_motion.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../../features/auth/presentation/mv2_account_avatar.dart';
import '../../features/shell/application/chrome_actions.dart';
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
    this.onSearch,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  /// Currently selected shell destination.
  final Mv2Tab current;

  /// Same callback as the floating bar, so both chromes switch branches
  /// identically (haptics, attribution, chrome reset).
  final ValueChanged<Mv2Tab> onSelect;

  final int notificationUnread;

  /// Opens search; the toolbar's fallback action when the page publishes none.
  final VoidCallback? onSearch;

  /// Height the system's own status column occupies at the top of the strip.
  final double topInset;

  /// Safe-area inset at the bottom of the window.
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageActions =
        ref.watch(toolbarActionsProvider) ?? const <Mv2ToolbarAction>[];

    return Padding(
      // Clear the system chrome first; each cluster then keeps its own margin
      // inside what is left of the strip.
      padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
      child: Column(
        // Two distinct clusters, not one continuous bar (Apple's Duo mockups):
        // the tab bar is pinned to the bottom, the toolbar sits right below the
        // system's column and scrolls if a page offers more actions than the
        // strip's height can show at once.
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                child: _Cluster(
                  child: _ToolbarSection(
                    actions: pageActions,
                    onSearch: onSearch,
                  ),
                ),
              ),
            ),
          ),
          _Cluster(
            child: _TabBarSection(
              current: current,
              onSelect: onSelect,
              notificationUnread: notificationUnread,
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(
        horizontal: Mv2Spacing.x2,
        vertical: Mv2Spacing.x2,
      ),
      child: Mv2GlassSurface(
        borderRadius: Mv2Radius.nav,
        blur: 20,
        padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x3),
        child: child,
      ),
    );
  }
}

/// The strip's toolbar: the current page's actions, or 搜索 / 账号.
class _ToolbarSection extends StatelessWidget {
  const _ToolbarSection({required this.actions, this.onSearch});

  final List<Mv2ToolbarAction> actions;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shown = actions.take(maxToolbarActions);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (actions.isNotEmpty)
          for (final action in shown)
            _ChromeTile(
              semanticsLabel: action.label,
              label: action.label,
              labelColor: action.active
                  ? colors.accent
                  : colors.textTertiary,
              onTap: action.onTap,
              leading: Icon(
                action.active ? (action.activeIcon ?? action.icon) : action.icon,
                size: 22,
                color: action.active ? colors.accent : colors.textSecondary,
              ),
            )
        else ...<Widget>[
          if (onSearch != null)
            _ChromeTile(
              semanticsLabel: '搜索',
              label: '搜索',
              labelColor: colors.textTertiary,
              onTap: onSearch!,
              leading: Icon(
                Icons.search_rounded,
                size: 22,
                color: colors.textSecondary,
              ),
            ),
          const SizedBox(height: Mv2Spacing.x2),
          const Mv2AccountAvatar(size: 32),
        ],
      ],
    );
  }
}

/// The strip's tab bar: the five shell destinations.
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

/// Icon + label column shared by both sections.
class _ChromeTile extends StatelessWidget {
  const _ChromeTile({
    required this.leading,
    required this.label,
    required this.labelColor,
    required this.onTap,
    required this.semanticsLabel,
    this.selected = false,
  });

  final Widget leading;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;
  final String semanticsLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              leading,
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: Mv2Motion.tab,
                style: context.text.tabLabel.copyWith(color: labelColor),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

    return _ChromeTile(
      selected: selected,
      semanticsLabel: spec.label,
      label: spec.label,
      labelColor: fg,
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Icon(selected ? spec.activeIcon : spec.icon, size: 22, color: fg),
          if (badgeCount > 0)
            Positioned(
              right: -7,
              top: -5,
              child: _ChromeBadge(count: badgeCount),
            ),
        ],
      ),
    );
  }
}

class _TabBarPublish extends StatelessWidget {
  const _TabBarPublish({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _ChromeTile(
      semanticsLabel: '发布',
      label: '发布',
      labelColor: colors.textTertiary,
      onTap: onTap,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colors.accent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.add_rounded,
          size: 20,
          color: colors.accentContrast,
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
