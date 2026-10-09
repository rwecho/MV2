import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/v2ex_providers.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import 'mv2_page_header.dart';
import '../primitives/mv2_buttons.dart';
import 'adaptive/mv2_adaptive_destinations.dart';
import '../../features/settings/application/settings_controller.dart';
import 'package:mv2/ui/components/adaptive/mv2_tabs.dart';

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
    this.appBar,
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

  /// Toolbar for pages whose top bar is not an [Mv2PageHeader] (a topic's own
  /// bar with a back affordance, say). Takes precedence over [header].
  final AdaptiveAppBar? appBar;

  /// Extra bottom padding a scrollable must reserve so its last row clears the
  /// floating bar.
  static double bottomContentInset(BuildContext context) =>
      mv2BarContentInset(context);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Quietly tells the user the content is stale, so "the app works but this
    // one page fails" is never mistaken for a broken page.
    final fromCache = ref.watch(cacheFallbackProvider);
    // 设置 → 内容宽度. Applied to the reading column only.
    final contentWidth = ref.watch(
      settingsProvider.select((AppSettings s) => s.contentWidth),
    );

    // The page's header becomes the *fixed* toolbar: `adaptive_platform_ui`'s
    // chrome draws one persistent bar whose items change as pages come and go
    // (and, on the Duo, the same items in the trailing capsule bar). A header
    // that is not an [Mv2PageHeader] — a segmented control, a topic top bar —
    // still renders in the body.
    final headerWidget = header;
    final pageHeader = headerWidget is Mv2PageHeader ? headerWidget : null;
    final explicitAppBar = appBar;
    final effectiveAppBar = explicitAppBar ??
        (pageHeader == null
            ? null
            : AdaptiveAppBar(
                title: pageHeader.title,
                subtitle: pageHeader.subtitle,
                actions: <AdaptiveAppBarAction>[
                  for (final Widget action in pageHeader.actions)
                    if (action is Mv2IconButton)
                      AdaptiveAppBarAction(
                        iosSymbol: mv2SfSymbolFor(action.icon),
                        icon: action.icon,
                        iconWidget: Icon(action.icon),
                        label: action.tooltip ?? pageHeader.title,
                        onPressed: action.onPressed ?? () {},
                      )
                    else
                      // Custom header widgets (the account avatar, a draft
                      // status label) ride along as an item so nothing the page
                      // put in its header disappears.
                      AdaptiveAppBarAction(
                        iconWidget: action,
                        label: '',
                        onPressed: () {},
                      ),
                ],
              ));

    return AdaptiveScaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: _collapsedForLegacyIOS(effectiveAppBar),
      body: Stack(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth.maxWidth),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: <Widget>[
                      if (pageHeader == null && explicitAppBar == null)
                        ?headerWidget,
                      if (fromCache) const _OfflineNotice(),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Page-level bottom bar (the composer's action row). The shell's own
          // tab bar is `adaptive_platform_ui`'s now, not this.
          if (bottomBar != null)
            Positioned(left: 0, right: 0, bottom: 0, child: bottomBar!),
        ],
      ),
    );
  }
}

/// On iOS 25 and below (no fixed chrome, no native overflow) a bar full of
/// buttons reads as clutter: collapse everything into one ellipsis button
/// whose menu (an action sheet on these versions) re-offers every action.
/// iOS 26+ keeps the per-item buttons — the native toolbar and the Duo's
/// trailing capsule bar are designed for them.
AdaptiveAppBar? _collapsedForLegacyIOS(AdaptiveAppBar? bar) {
  if (bar == null) return null;
  if (!PlatformInfo.isIOS || PlatformInfo.isIOS26OrHigher()) return bar;
  final actions = bar.actions;
  if (actions == null || actions.length <= 1) return bar;
  return AdaptiveAppBar(
    title: bar.title,
    subtitle: bar.subtitle,
    titleWidget: bar.titleWidget,
    actions: <AdaptiveAppBarAction>[
      AdaptiveAppBarAction(
        icon: Icons.more_horiz,
        label: '更多',
        iconWidget: AdaptivePopupMenuButton.icon<int>(
          icon: CupertinoIcons.ellipsis,
          size: 38,
          items: <AdaptivePopupMenuItem<int>>[
            for (var i = 0; i < actions.length; i++)
              AdaptivePopupMenuItem<int>(
                value: i,
                label: actions[i].effectiveLabel ?? '',
                icon: actions[i].icon,
              ),
          ],
          onSelected: (index, _) {
            if (index >= 0 && index < actions.length) {
              actions[index].onPressed();
            }
          },
        ),
        onPressed: () {},
      ),
    ],
  );
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
