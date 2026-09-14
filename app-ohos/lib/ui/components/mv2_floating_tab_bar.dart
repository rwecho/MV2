import 'package:flutter/material.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_motion.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';

/// The five fixed MV2 destinations (`docs/01` §3).
enum Mv2Tab { feed, nodes, publish, notifications, profile }

/// Floating, frosted bottom navigation (`designs/01-home-feed.png`).
///
/// Deliberately **not** a Material `BottomNavigationBar`, and the publish
/// action is a 38px accent circle rather than a large FAB
/// (`agent/AGENTS.md` UI 禁止项).
class Mv2FloatingTabBar extends StatelessWidget {
  const Mv2FloatingTabBar({
    super.key,
    required this.current,
    required this.onSelect,
    this.notificationUnread = 0,
  });

  final Mv2Tab current;
  final ValueChanged<Mv2Tab> onSelect;
  final int notificationUnread;

  static const double height = 62;
  static const double bottomGap = 10;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: Mv2Spacing.pageNarrow,
        right: Mv2Spacing.pageNarrow,
        bottom: bottomInset > 0 ? bottomInset : bottomGap,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: Mv2Spacing.maxContentWidth,
          ),
          child: Mv2GlassSurface(
            borderRadius: Mv2Radius.nav,
            blur: 20,
            child: SizedBox(
              height: height,
              child: Row(
                children: <Widget>[
                  _TabButton(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: '首页',
                    selected: current == Mv2Tab.feed,
                    onTap: () => onSelect(Mv2Tab.feed),
                  ),
                  _TabButton(
                    icon: Icons.grid_view_outlined,
                    activeIcon: Icons.grid_view_rounded,
                    label: '节点',
                    selected: current == Mv2Tab.nodes,
                    onTap: () => onSelect(Mv2Tab.nodes),
                  ),
                  _PublishButton(onTap: () => onSelect(Mv2Tab.publish)),
                  _TabButton(
                    icon: Icons.notifications_none_rounded,
                    activeIcon: Icons.notifications_rounded,
                    label: '通知',
                    selected: current == Mv2Tab.notifications,
                    onTap: () => onSelect(Mv2Tab.notifications),
                    badgeCount: notificationUnread,
                  ),
                  _TabButton(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: '我的',
                    selected: current == Mv2Tab.profile,
                    onTap: () => onSelect(Mv2Tab.profile),
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

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? colors.accent : colors.textTertiary;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: Mv2FloatingTabBar.height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Icon(selected ? activeIcon : icon, size: 22, color: fg),
                    if (badgeCount > 0)
                      Positioned(
                        right: -7,
                        top: -5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          constraints: const BoxConstraints(minWidth: 15),
                          decoration: BoxDecoration(
                            color: colors.danger,
                            borderRadius: Mv2Radius.pill,
                          ),
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            textAlign: TextAlign.center,
                            style: context.text.tabLabel.copyWith(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: Mv2Motion.tab,
                  style: context.text.tabLabel.copyWith(color: fg),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PublishButton extends StatelessWidget {
  const _PublishButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: Semantics(
        button: true,
        label: '发布',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: Mv2FloatingTabBar.height,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 22,
                      color: colors.accentContrast,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '发布',
                    style: context.text.tabLabel.copyWith(
                      color: colors.textTertiary,
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
