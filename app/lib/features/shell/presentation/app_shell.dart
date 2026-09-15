import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_motion.dart';
import '../../../ui/components/mv2_floating_tab_bar.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/mv2_haptics.dart';
import '../../../ui/utils/mv2_breakpoints.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_session.dart';
import '../../composer/presentation/composer_sheets.dart';
import '../../notifications/application/notifications_providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../topic/presentation/topic_detail_page.dart';
import '../application/shell_chrome.dart';
import '../application/tablet_topic_pane.dart';

/// Shell that hosts the four tabbed branches and paints the floating tab bar
/// over them, so the bar does not rebuild or animate when switching tabs.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Guards the expiry SnackBar so a rebuild/notifier replay cannot show it
  /// twice; reset as soon as the session becomes usable again.
  bool _expiryHandled = false;

  /// One startup revalidation per app run (refreshes the unread badge).
  bool _revalidatedSession = false;

  Mv2Tab get _current => switch (widget.navigationShell.currentIndex) {
    0 => Mv2Tab.feed,
    1 => Mv2Tab.nodes,
    2 => Mv2Tab.notifications,
    _ => Mv2Tab.profile,
  };

  void _onSelect(BuildContext context, Mv2Tab tab) {
    // Entering a branch always shows the chrome again, even if the previous
    // branch was scrolled far enough to hide the bar.
    ref.read(shellBarCollapsedProvider.notifier).reset();
    // 设置 → 触觉反馈.
    Mv2Haptics.tap(ref.read(settingsProvider).hapticsEnabled);
    if (tab == Mv2Tab.publish) {
      showPublishComposer(context);
      return;
    }
    final index = switch (tab) {
      Mv2Tab.feed => 0,
      Mv2Tab.nodes => 1,
      Mv2Tab.notifications => 2,
      _ => 3,
    };
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  /// Surfaces an expired session once, with a shortcut back into the WebView
  /// login flow.
  void _onAuthChanged(
    AsyncValue<AuthSession>? previous,
    AsyncValue<AuthSession> next,
  ) {
    if (next.value?.isSignedIn ?? false) {
      _expiryHandled = false;
      return;
    }
    if (_expiryHandled) return;
    final reason = ref.read(authControllerProvider.notifier).lastSignOutReason;
    if (reason != SignOutReason.sessionExpired) return;
    _expiryHandled = true;
    // Defer past the current build/frame: the listener can fire while the tree
    // is being laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('登录状态已失效，请重新登录'),
          action: SnackBarAction(
            label: '重新登录',
            onPressed: () {
              if (mounted) context.push('/login');
            },
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AuthSession>>(authControllerProvider, _onAuthChanged);
    // A stored session carries no notification count, so revalidate once it
    // loads: that refreshes the avatar / unread badge from the server and signs
    // an expired cookie out before the first action fails.
    ref.listen<AsyncValue<AuthSession>>(authControllerProvider, (
      previous,
      next,
    ) {
      final session = next.value;
      if (_revalidatedSession || session == null || !session.isSignedIn) {
        return;
      }
      if (previous?.value?.isSignedIn ?? false) return;
      _revalidatedSession = true;
      unawaited(ref.read(authControllerProvider.notifier).refreshAccount());
    });
    final barCollapsed = ref.watch(shellBarCollapsedProvider);
    final twoPane = mv2IsTwoPane(context);
    final windowWidth = MediaQuery.sizeOf(context).width;
    final splitRatio = ref.watch(
      settingsProvider.select((AppSettings s) => s.splitRatio),
    );
    // The user's ratio, laid out against the *current* window so rotation
    // re-derives a sane width; clamps keep both panes usable.
    final leftWidth = twoPane
        ? (windowWidth * splitRatio).clamp(
            minPaneWidth,
            windowWidth - paneDividerWidth - minDetailWidth,
          )
        : windowWidth;

    // The left pane is always a fixed-width `SizedBox` — never swapped for an
    // `Expanded` on phones. A type change at this slot would reparent the
    // navigationShell and discard all four branches' navigator state when the
    // window crosses the two-pane breakpoint. On phones the width is the whole
    // window, pixel-identical to the previous Stack layout.
    return Row(
      children: <Widget>[
        SizedBox(
          width: leftWidth,
          child: Stack(
            children: <Widget>[
              widget.navigationShell,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSlide(
                  // Slide the whole padded bar (bar + safe area) below the
                  // viewport.
                  offset: barCollapsed ? const Offset(0, 1.2) : Offset.zero,
                  duration: Mv2Motion.sheet,
                  curve: Mv2Motion.standard,
                  child: Mv2FloatingTabBar(
                    current: _current,
                    onSelect: (tab) => _onSelect(context, tab),
                    notificationUnread: ref.watch(notificationUnreadProvider),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Two-pane: opened topics render beside the lists instead of pushing
        // a full-screen route (see `openTopic`). The divider doubles as the
        // drag handle for the pane split.
        if (twoPane) ...<Widget>[
          _PaneDivider(
            key: const Key('pane_divider'),
            leftWidth: leftWidth,
            windowWidth: windowWidth,
            onDrag:
                (leftWidth) => ref
                    .read(settingsProvider.notifier)
                    .setSplitRatio(leftWidth / windowWidth),
          ),
          const Expanded(child: _TabletDetailPane()),
        ],
      ],
    );
  }
}

/// Widths for the two-pane split: the list pane never gets narrower than a
/// readable card column, and the detail pane always keeps room for its
/// centred reading column.
const double paneDividerWidth = 24.0;
const double minPaneWidth = 320.0;
const double minDetailWidth = 420.0;

/// The draggable handle between the two panes: a hairline that widens into an
/// accent bar while dragging, with a finger-sized (24pt) hit strip. The strip
/// is its own gesture area, so it never competes with the list's horizontal
/// page swipes.
class _PaneDivider extends StatefulWidget {
  const _PaneDivider({
    super.key,
    required this.leftWidth,
    required this.windowWidth,
    required this.onDrag,
  });

  final double leftWidth;
  final double windowWidth;
  final ValueChanged<double> onDrag;

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  bool _dragging = false;
  double? _dragStartLeft;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) {
          setState(() {
            _dragging = true;
            _dragStartLeft = widget.leftWidth;
          });
        },
        onHorizontalDragUpdate: (details) {
          widget.onDrag(
            (_dragStartLeft! + details.delta.dx).clamp(
              minPaneWidth,
              widget.windowWidth - paneDividerWidth - minDetailWidth,
            ),
          );
        },
        onHorizontalDragEnd: (details) {
          setState(() {
            _dragging = false;
            _dragStartLeft = null;
          });
        },
        child: SizedBox(
          width: paneDividerWidth,
          child: Center(
            child: Container(
              width: _dragging ? 3.0 : 1.0,
              height: double.infinity,
              color: _dragging ? colors.accent : Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// The tablet layout's right-hand pane: the currently opened topic, or an
/// empty state before the first selection.
class _TabletDetailPane extends ConsumerWidget {
  const _TabletDetailPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(tabletTopicPaneProvider);
    if (selection == null) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: const Center(
          child: Mv2StateView(
            kind: Mv2StateKind.empty,
            title: '未选择主题',
            description: '从左侧选择一个主题，它会在这里打开。',
          ),
        ),
      );
    }
    // Keyed so a new selection starts the detail page fresh (scroll position,
    // collapsed chrome) instead of inheriting the previous topic's state.
    return KeyedSubtree(
      key: ValueKey('${selection.topicId}:${selection.floor}'),
      child: TopicDetailPage(
        topicId: selection.topicId,
        initialFloor: selection.floor,
        inPane: true,
      ),
    );
  }
}
