import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/v2ex_providers.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import 'mv2_floating_tab_bar.dart';

/// Shared page frame for the primary (tabbed) and secondary pages.
///
/// The floating tab bar is painted **over** the scrollable so content slides
/// beneath the glass, matching the mockups. Pages must therefore add
/// [bottomContentInset] to their scroll padding.
class Mv2PageScaffold extends ConsumerWidget {
  const Mv2PageScaffold({
    super.key,
    required this.child,
    this.header,
    this.currentTab,
    this.onTabSelect,
    this.notificationUnread = 0,
    this.bottomBar,
    this.resizeToAvoidBottomInset = true,
  });

  /// Usually a `CustomScrollView` / `ListView`.
  final Widget child;

  /// Fixed (non-scrolling) top area: page header + segmented control.
  final Widget? header;

  final Mv2Tab? currentTab;
  final ValueChanged<Mv2Tab>? onTabSelect;
  final int notificationUnread;

  /// Bottom overlay alternative to the tab bar (e.g. `FloatingReplyBar`).
  final Widget? bottomBar;

  final bool resizeToAvoidBottomInset;

  /// Extra bottom padding a scrollable must reserve so its last row clears the
  /// floating bar.
  static double bottomContentInset(BuildContext context) {
    final safe = MediaQuery.viewPaddingOf(context).bottom;
    return Mv2FloatingTabBar.height +
        Mv2FloatingTabBar.bottomGap +
        (safe > 0 ? safe : 0) +
        Mv2Spacing.x3;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final hasTabBar = currentTab != null;
    // Quietly tells the user the content is stale, so "the app works but this
    // one page fails" is never mistaken for a broken page.
    final fromCache = ref.watch(cacheFallbackProvider);

    return Scaffold(
      backgroundColor: colors.background,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: Stack(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                ?header,
                if (fromCache) const _OfflineNotice(),
                Expanded(child: child),
              ],
            ),
          ),
          if (hasTabBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Mv2FloatingTabBar(
                current: currentTab!,
                onSelect: onTabSelect ?? (_) {},
                notificationUnread: notificationUnread,
              ),
            ),
          if (bottomBar != null)
            Positioned(left: 0, right: 0, bottom: 0, child: bottomBar!),
        ],
      ),
    );
  }
}

/// Slim strip shown while anonymous content is served from the disk cache.
class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Mv2Spacing.pageNarrow,
        vertical: Mv2Spacing.x1,
      ),
      color: colors.accentSoft,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.cloud_off_rounded, size: 14, color: colors.accent),
          const SizedBox(width: Mv2Spacing.x1),
          Text(
            '离线内容 · 来自本地缓存',
            style: context.text.metadata.copyWith(color: colors.accent),
          ),
        ],
      ),
    );
  }
}
