// The chrome's own layout constants: the host draws its bar over the content
// (iOS 26 Liquid Glass), so pinned page content has to keep clear of it. The
// package does not export these, and re-implementing the heights would drift.
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart'
    show kDuoTitleBandHeight;
import 'package:adaptive_platform_ui/src/toolbar/hosted_top_toolbar.dart'
    show kHostedToolbarHeight;
import 'package:adaptive_platform_ui/src/toolbar/toolbar_chrome_scope.dart'
    show ToolbarChromeScope;

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

/// Height a page should keep clear at the bottom for the bar plus its home
/// indicator, so scrolling content ends above it rather than underneath.
///
/// The bar is `adaptive_platform_ui`'s now: a native UITabBar on iOS 26+ (or
/// its Material/Cupertino fallback elsewhere), all of which are ~80pt tall
/// including their own padding.
double mv2BarContentInset(BuildContext context) {
  final safe = MediaQuery.viewPaddingOf(context).bottom;
  return 80 + (safe > 0 ? safe : 0) + 12;
}

/// SF Symbol for the icons our page headers use, so the native toolbar (and
/// the Duo's trailing capsule bar, which draws only `iosSymbol`) shows the
/// same affordance as the Cupertino/Material paths.
String? mv2SfSymbolFor(IconData icon) {
  if (icon == Icons.settings_outlined || icon == Icons.settings) {
    return 'gearshape';
  }
  if (icon == Icons.search_rounded || icon == Icons.search) {
    return 'magnifyingglass';
  }
  if (icon == Icons.filter_list_rounded || icon == Icons.filter_list) {
    return 'line.3.horizontal.decrease';
  }
  if (icon == Icons.more_horiz_rounded || icon == Icons.more_horiz) {
    return 'ellipsis';
  }
  if (icon == Icons.ios_share_rounded || icon == Icons.ios_share) {
    return 'square.and.arrow.up';
  }
  if (icon == Icons.add_rounded || icon == Icons.add) return 'plus';
  if (icon == Icons.refresh_rounded || icon == Icons.refresh) {
    return 'arrow.clockwise';
  }
  if (icon == Icons.star_border_rounded) return 'star';
  if (icon == Icons.star_rounded) return 'star.fill';
  if (icon == Icons.favorite_border_rounded) return 'heart';
  if (icon == Icons.favorite_rounded) return 'heart.fill';
  return null;
}

/// Top inset pinned page content must keep so it sits **below** the fixed
/// toolbar chrome instead of underneath it.
///
/// The host draws its bar over the page (that is the iOS 26 look: lists scroll
/// beneath the translucent bar), so scrolling content is fine — but a pinned
/// control (the feed's tab strip, 通知's segmented tabs) would be covered by
/// it, as the unfolded Duo screenshot showed.
double mv2ChromeTopInset(BuildContext context) {
  final scope = ToolbarChromeScope.maybeOf(context);
  if (scope == null || !scope.hostsToolbar) return 0;
  // The Duo shows the title alone in a band at the top; other iOS 26+ devices
  // draw the toolbar beneath the status bar.
  if (scope.hostsDuoControls) return kDuoTitleBandHeight;
  return kHostedToolbarHeight + MediaQuery.paddingOf(context).top;
}
