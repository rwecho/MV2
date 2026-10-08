import 'package:flutter/material.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_motion.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../../features/auth/presentation/mv2_account_avatar.dart';
import 'mv2_floating_tab_bar.dart';

/// Vertical chrome rail for the iPhone Duo's trailing edge strip.
///
/// The Duo keeps a wide safe-area strip along its sensor-bar edge in **both**
/// states (folded cover display and unfolded inner display), and iOS itself
/// parks the Dynamic Island plus the vertical status column there. Apple's
/// guidance for the device ("Designing for iPhone Duo") is to keep the toolbar
/// and the tab bar in that same strip, below the system's own items.
///
/// This rail follows that layout:
///
/// * leading segment — page actions (搜索 / 账号), the *toolbar* stand-in;
/// * trailing segment — the five shell destinations, the *tab bar* stand-in.
///
/// [topInset] clears the system's status column (see `mv2RailTopInset`), so our
/// controls never land under the Dynamic Island or the status items. The rail
/// draws inside the inset the window already reserves, so the panes keep their
/// full width and win back the bottom bar's height. Devices without such a strip
/// keep [Mv2FloatingTabBar].
class Mv2TrailingRail extends StatelessWidget {
  const Mv2TrailingRail({
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

  /// Opens search; hidden when the shell has no search route.
  final VoidCallback? onSearch;

  /// Height the system's own status column occupies at the top of the strip.
  final double topInset;

  /// Safe-area inset at the bottom of the window.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Clear the system chrome first, then float the glass column inside the
      // remaining strip.
      padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x2,
          vertical: Mv2Spacing.x2,
        ),
        child: Mv2GlassSurface(
          borderRadius: Mv2Radius.nav,
          blur: 20,
          padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x3),
          child: Column(
            // Two groups, spread apart: page actions right below the system's
            // column (cleared by [topInset]) and the destinations along the
            // bottom — the arrangement Apple's own Duo mockups use for the
            // toolbar and tab bar inside this strip.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (onSearch != null)
                    _RailAction(
                      icon: Icons.search_rounded,
                      label: '搜索',
                      onTap: onSearch!,
                    ),
                  const SizedBox(height: Mv2Spacing.x2),
                  const Mv2AccountAvatar(size: 32),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final spec in mv2TabSpecs)
                    if (spec.tab == Mv2Tab.publish)
                      _RailPublish(onTap: () => onSelect(spec.tab))
                    else
                      _RailTab(
                        spec: spec,
                        selected: current == spec.tab,
                        badgeCount: spec.tab == Mv2Tab.notifications
                            ? notificationUnread
                            : 0,
                        onTap: () => onSelect(spec.tab),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + label row shared by the rail's tab items and its search action.
class _RailTile extends StatelessWidget {
  const _RailTile({
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

class _RailTab extends StatelessWidget {
  const _RailTab({
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

    return _RailTile(
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
              child: _RailBadge(count: badgeCount),
            ),
        ],
      ),
    );
  }
}

class _RailPublish extends StatelessWidget {
  const _RailPublish({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _RailTile(
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

class _RailAction extends StatelessWidget {
  const _RailAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _RailTile(
      semanticsLabel: label,
      label: label,
      labelColor: colors.textTertiary,
      onTap: onTap,
      leading: Icon(icon, size: 22, color: colors.textSecondary),
    );
  }
}

class _RailBadge extends StatelessWidget {
  const _RailBadge({required this.count});

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
