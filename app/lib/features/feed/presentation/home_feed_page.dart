import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/home_tab.dart';
import '../../../design_system/tokens/mv2_motion.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_refreshable.dart';
import '../../../ui/components/mv2_scroll_collapse.dart';
import '../../../ui/components/mv2_tab_strip.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/components/topic_item.dart';
import '../../../ui/components/xna_item.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../auth/presentation/mv2_account_avatar.dart';
import '../../shell/application/shell_chrome.dart';
import '../../topic/application/open_topic.dart';
import '../application/feed_providers.dart';

/// Home feed page.
///
/// The top row mirrors V2EX's own `#Tabs` (`技术 … VXNA`) instead of the four
/// ad-hoc segments from `designs/01-home-feed.png`; see
/// `docs/11-design-implementation-notes.md` (D14). The body is a horizontal
/// [PageView], so swiping the content moves between tabs and stays in sync with
/// the strip (both directions). The floating tab bar is drawn by `AppShell`, so
/// no `currentTab` is passed to [Mv2PageScaffold].
class HomeFeedPage extends ConsumerStatefulWidget {
  const HomeFeedPage({super.key});

  @override
  ConsumerState<HomeFeedPage> createState() => _HomeFeedPageState();
}

class _HomeFeedPageState extends ConsumerState<HomeFeedPage> {
  late final PageController _pageController;

  /// True while a tap-driven page animation is running, so the provider
  /// listener does not fight the explicit `animateToPage`.
  bool _animatingFromTap = false;

  /// True while the page header is shrunk to just the tab row.
  bool _headerCollapsed = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: ref.read(homeTabProvider).index,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Reading down hides the big header (and the shell's bottom bar); scrolling
  /// back brings them in again. Horizontal PageView scrolls are ignored by
  /// [mv2CollapseFromScroll].
  bool _onScrollNotification(ScrollNotification notification) {
    final collapsed = mv2CollapseFromScroll(notification);
    if (collapsed != null && collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
      ref.read(shellBarCollapsedProvider.notifier).set(collapsed);
    }
    return false;
  }

  void _onTabSelected(int index) {
    _animatingFromTap = true;
    ref.read(homeTabProvider.notifier).select(HomeTab.values[index]);
    _pageController
        .animateToPage(
          index,
          duration: Mv2Motion.tab,
          curve: Mv2Motion.standard,
        )
        .whenComplete(() => _animatingFromTap = false);
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeTabProvider);

    // Selection can also change outside a swipe — restoring the persisted tab
    // after hydration. Jump (not animate) there so launch does not sweep across
    // the whole row.
    ref.listen<HomeTab>(homeTabProvider, (previous, next) {
      if (_animatingFromTap || !_pageController.hasClients) return;
      if (_pageController.page?.round() == next.index) return;
      _pageController.jumpToPage(next.index);
    });

    return Mv2PageScaffold(
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Reading down shrinks the page header away so only the tab row
          // stays; scrolling back expands it.
          AnimatedSize(
            duration: Mv2Motion.sheet,
            curve: Mv2Motion.standard,
            alignment: Alignment.topCenter,
            child: _headerCollapsed
                ? const SizedBox(width: double.infinity, height: 0)
                : Mv2PageHeader(
                    title: 'MV2',
                    subtitle: 'Wake Up to V2EX',
                    actions: <Widget>[
                      Mv2IconButton(
                        icon: Icons.search_rounded,
                        filled: true,
                        onPressed: () => context.push('/feed/search'),
                      ),
                      const SizedBox(width: Mv2Spacing.x2),
                      const Mv2AccountAvatar(),
                    ],
                  ),
          ),
          Mv2TabStrip(
            labels: <String>[for (final tab in HomeTab.values) tab.label],
            selectedIndex: tab.index,
            onChanged: _onTabSelected,
          ),
          const SizedBox(height: Mv2Spacing.x3),
        ],
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: PageView.builder(
          controller: _pageController,
          itemCount: HomeTab.values.length,
          onPageChanged: (index) =>
              ref.read(homeTabProvider.notifier).select(HomeTab.values[index]),
          itemBuilder: (context, index) {
            final pageTab = HomeTab.values[index];
            return pageTab.isAggregator
                ? const _XnaFeedBody()
                : _TopicFeedBody(tab: pageTab);
          },
        ),
      ),
    );
  }
}

/// Topic-list tab (`/?tab={slug}`).
class _TopicFeedBody extends ConsumerWidget {
  const _TopicFeedBody({required this.tab});

  final HomeTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = Mv2PageScaffold.bottomContentInset(context);
    Future<void> refresh() => ref.refresh(feedProvider(tab).future);
    ref.listen(feedProvider(tab), (p, n) => mv2ToastLoadError(context, p, n));

    return ref
        .watch(feedProvider(tab))
        .when(
          skipLoadingOnReload: true,
          data: (topics) {
            if (topics.isEmpty) {
              return Mv2RefreshableFill(
                onRefresh: refresh,
                child: const Mv2StateView(kind: Mv2StateKind.empty),
              );
            }
            return Mv2Refreshable(
              onRefresh: refresh,
              child: ListView.separated(
                // Per-tab storage so a swipe away and back restores the offset.
                key: PageStorageKey<String>('home-feed-${tab.name}'),
                // Short lists must still be pullable.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  Mv2Spacing.pageNarrow,
                  0,
                  Mv2Spacing.pageNarrow,
                  bottomInset,
                ),
                itemCount: topics.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: Mv2Spacing.x3),
                itemBuilder: (context, index) {
                  final topic = topics[index];
                  return TopicItem(
                    topic: topic,
                    onTap: () => openTopic(context, topic.id),
                  );
                },
              ),
            );
          },
          loading: () => Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: const TopicListSkeleton(),
          ),
          error: (_, _) => Mv2RefreshableFill(
            onRefresh: refresh,
            child: Mv2StateView(
              kind: Mv2StateKind.error,
              actionLabel: '重试',
              onAction: () => ref.invalidate(feedProvider(tab)),
            ),
          ),
        );
  }
}

/// The VXNA aggregator tab (`/xna`): external articles, not on-site topics.
class _XnaFeedBody extends ConsumerWidget {
  const _XnaFeedBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = Mv2PageScaffold.bottomContentInset(context);
    Future<void> refresh() => ref.refresh(xnaFeedProvider.future);
    ref.listen(xnaFeedProvider, (p, n) => mv2ToastLoadError(context, p, n));

    return ref
        .watch(xnaFeedProvider)
        .when(
          skipLoadingOnReload: true,
          data: (entries) {
            if (entries.isEmpty) {
              return Mv2RefreshableFill(
                onRefresh: refresh,
                child: const Mv2StateView(kind: Mv2StateKind.empty),
              );
            }
            return Mv2Refreshable(
              onRefresh: refresh,
              child: ListView.separated(
                key: const PageStorageKey<String>('home-feed-vxna'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  Mv2Spacing.pageNarrow,
                  0,
                  Mv2Spacing.pageNarrow,
                  bottomInset,
                ),
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: Mv2Spacing.x3),
                itemBuilder: (context, index) => XnaItem(entry: entries[index]),
              ),
            );
          },
          loading: () => Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: const TopicListSkeleton(),
          ),
          error: (_, _) => Mv2RefreshableFill(
            onRefresh: refresh,
            child: Mv2StateView(
              kind: Mv2StateKind.error,
              actionLabel: '重试',
              onAction: () => ref.invalidate(xnaFeedProvider),
            ),
          ),
        );
  }
}
