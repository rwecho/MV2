import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The five shell destinations in `adaptive_platform_ui` terms.
///
/// Same entries, order, labels and unread badge as the app has always had;
/// only the icon vocabulary changes per platform, which is what the package
/// needs to hand the bar to the system: an SF Symbol name on iOS 26+, a
/// Cupertino icon on older iOS, a Material icon everywhere else.
///
/// 发布 stays a *destination* in the bar and an action in behaviour: the shell
/// intercepts it and opens the composer instead of switching branch, exactly
/// as `selectShellTab` has always done.
List<AdaptiveNavigationDestination> mv2AdaptiveDestinations({
  required int notificationUnread,
}) {
  final ios26 = PlatformInfo.isIOS26OrHigher();
  final ios = PlatformInfo.isIOS;

  return <AdaptiveNavigationDestination>[
    AdaptiveNavigationDestination(
      icon: ios26
          ? 'house.fill'
          : ios
          ? CupertinoIcons.home
          : Icons.home_outlined,
      selectedIcon: ios26
          ? 'house.fill'
          : ios
          ? CupertinoIcons.home
          : Icons.home_rounded,
      label: '首页',
    ),
    AdaptiveNavigationDestination(
      icon: ios26
          ? 'square.grid.2x2'
          : ios
          ? CupertinoIcons.square_grid_2x2
          : Icons.grid_view_outlined,
      selectedIcon: ios26
          ? 'square.grid.2x2.fill'
          : ios
          ? CupertinoIcons.square_grid_2x2
          : Icons.grid_view_rounded,
      label: '节点',
    ),
    AdaptiveNavigationDestination(
      icon: ios26 ? 'plus' : ios ? CupertinoIcons.add : Icons.add_rounded,
      label: '发布',
    ),
    AdaptiveNavigationDestination(
      icon: ios26
          ? 'bell'
          : ios
          ? CupertinoIcons.bell
          : Icons.notifications_none_rounded,
      selectedIcon: ios26
          ? 'bell.fill'
          : ios
          ? CupertinoIcons.bell
          : Icons.notifications_rounded,
      label: '通知',
      badgeCount: notificationUnread,
    ),
    AdaptiveNavigationDestination(
      icon: ios26
          ? 'person'
          : ios
          ? CupertinoIcons.person
          : Icons.person_outline_rounded,
      selectedIcon: ios26
          ? 'person.fill'
          : ios
          ? CupertinoIcons.person
          : Icons.person_rounded,
      label: '我的',
    ),
  ];
}

/// Bar index for a branch index: 发布 sits in the middle of the bar but is not
/// a branch, so the two orders differ.
const List<int> _barIndexForBranch = <int>[0, 1, 3, 4];

/// Bar index a branch highlights.
int mv2BarIndexForBranch(int branchIndex) =>
    _barIndexForBranch[branchIndex.clamp(0, _barIndexForBranch.length - 1)];
