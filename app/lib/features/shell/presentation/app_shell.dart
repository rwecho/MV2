import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:multi_split_view/multi_split_view.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_motion.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_floating_tab_bar.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/utils/mv2_breakpoints.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_session.dart';
import '../../notifications/application/notifications_providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../topic/presentation/topic_detail_page.dart';
import '../application/shell_chrome.dart';
import '../application/shell_tabs.dart';
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

  /// Owns the two-pane split sizes while the shell lives. Flex areas keep the
  /// "ratio" semantics (rotation re-derives widths), and the divider drag
  /// mutates these flexes directly — no provider writes per frame.
  MultiSplitViewController? _splitController;

  /// The settings ratio the controller flexes currently reflect, so an
  /// externally changed setting (initial load) syncs in exactly once.
  double? _syncedSplitRatio;

  /// True between divider drag start and end; while set, the build must not
  /// stomp the controller with the (stale) settings ratio.
  bool _draggingSplit = false;

  /// Reparents the left pane across the Row ↔ MultiSplitView structure change
  /// at the two-pane breakpoint: rotation across 900pt keeps the four branch
  /// navigators alive.
  final GlobalKey _leftPaneKey = GlobalKey(debugLabel: 'left_pane');

  /// Arbitrary flex scale; ratios map onto it so pixel floors can be
  /// expressed as flex mins for the current window width.
  static const double _splitFlexTotal = 1000.0;

  @override
  void dispose() {
    _splitController?.dispose();
    super.dispose();
  }

  Mv2Tab get _current => switch (widget.navigationShell.currentIndex) {
    0 => Mv2Tab.feed,
    1 => Mv2Tab.nodes,
    2 => Mv2Tab.notifications,
    _ => Mv2Tab.profile,
  };

  void _onSelect(BuildContext context, Mv2Tab tab) {
    // Shared with the programmatic entries (header avatar) so both behave like
    // a real tab tap: haptics, attribution, chrome reset, branch switch. The
    // bar is a sibling of the shell, not below it, so pass it explicitly.
    selectShellTab(context, ref, tab, shell: widget.navigationShell);
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

    // The left pane is always a fixed-width `SizedBox` — never swapped for an
    // `Expanded` on phones. A type change at this slot would reparent the
    // navigationShell and discard all four branches' navigator state when the
    // window crosses the two-pane breakpoint. On phones the width is the whole
    // window, pixel-identical to the previous Stack layout.
    // The canvas fill covers the two-pane divider strip: the scaffold
    // background lives inside each pane's `Scaffold`, so an unpainted strip
    // would show the raw window backing (black) between the panes.
    final Widget leftPane = KeyedSubtree(
      // The GlobalKey lets the pane subtree survive the Row ↔ MultiSplitView
      // structure change at the breakpoint: rotation across 900pt keeps the
      // four branch navigators alive.
      key: _leftPaneKey,
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
    );

    // Two-pane: opened topics render beside the lists instead of pushing a
    // full-screen route (see `openTopic`). The split divider doubles as the
    // drag handle for the pane split; sizes live in the controller, and the
    // settings ratio is written once per gesture (on drag end).
    return ColoredBox(
      color: context.colors.background,
      child: twoPane
          ? MultiSplitViewTheme(
              data: MultiSplitViewThemeData(
                dividerThickness: paneDividerThickness,
              ),
              child: _buildTwoPaneSplit(
                context,
                splitRatio: splitRatio,
                windowWidth: windowWidth,
                leftPane: leftPane,
              ),
            )
          : Row(
              children: <Widget>[
                SizedBox(width: windowWidth, child: leftPane),
              ],
            ),
    );
  }

  /// Builds the two-pane split. The controller is the single live source of
  /// pane sizes during a session; the settings ratio seeds it once, and every
  /// later reconciliation (external setting change, window resize floors) is
  /// deferred past the frame — mutating areas notifies the split view, which
  /// must not happen while the tree is building.
  Widget _buildTwoPaneSplit(
    BuildContext context, {
    required double splitRatio,
    required double windowWidth,
    required Widget leftPane,
  }) {
    final controller = _splitController;
    if (controller == null) {
      final created = MultiSplitViewController(
        areas: <Area>[
          Area(flex: splitRatio * _splitFlexTotal),
          Area(flex: (1 - splitRatio) * _splitFlexTotal),
        ],
      );
      _applySplitConstraints(created, windowWidth);
      _splitController = created;
      _syncedSplitRatio = splitRatio;
    } else if (!_draggingSplit && splitRatio != _syncedSplitRatio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _splitController == null || _draggingSplit) return;
        _splitController!.getArea(0).flex = splitRatio * _splitFlexTotal;
        _splitController!.getArea(1).flex = (1 - splitRatio) * _splitFlexTotal;
        _applySplitConstraints(_splitController!, windowWidth);
        _syncedSplitRatio = splitRatio;
        setState(() {});
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _splitController == null) return;
        _applySplitConstraints(_splitController!, windowWidth);
      });
    }
    return MultiSplitView(
      controller: controller,
      onDividerDragStart: (_) => _draggingSplit = true,
      onDividerDragEnd: (_) => _persistSplitRatio(windowWidth),
      dividerBuilder: (axis, index, resizable, dragging, highlighted,
              themeData) =>
          KeyedSubtree(
        key: const Key('pane_divider'),
        child: VerticalDivider(
          width: paneDividerThickness,
          thickness: dragging || highlighted ? 3.0 : 1.0,
          indent: Mv2Spacing.x6,
          endIndent: Mv2Spacing.x6,
          // Canvas-level hairline: `Mv2Colors.border`, the same token as every
          // card outline on the page canvas; accent while interacted with.
          color: dragging || highlighted
              ? context.colors.accent
              : context.colors.border,
        ),
      ),
      // v3 API: content is built per Area, identified by controller index.
      builder: (context, area) => _splitController != null && identical(area, _splitController!.getArea(0))
          ? leftPane
          : const _TabletDetailPane(),
    );
  }

  /// Pixel floors translated into flex units for the current window width:
  /// the list pane never gets narrower than a readable card column, and the
  /// detail pane always keeps room for its centred reading column. Flexes are
  /// fractions of the width *after* the divider strip, so the floors are too.
  void _applySplitConstraints(
    MultiSplitViewController controller,
    double windowWidth,
  ) {
    final flexAreaWidth = windowWidth - paneDividerThickness;
    final leftMinFlex = minPaneWidth / flexAreaWidth * _splitFlexTotal;
    final rightMinFlex = minDetailWidth / flexAreaWidth * _splitFlexTotal;
    if (controller.getArea(0).min != leftMinFlex) {
      controller.getArea(0).min = leftMinFlex;
    }
    if (controller.getArea(1).min != rightMinFlex) {
      controller.getArea(1).min = rightMinFlex;
    }
  }

  /// Writes the post-drag split back into settings once — the drag itself only
  /// mutates the controller, so no disk write or shell rebuild happens per
  /// frame.
  void _persistSplitRatio(double windowWidth) {
    _draggingSplit = false;
    final controller = _splitController;
    if (controller == null) return;
    final leftFlex = controller.getArea(0).flex;
    final rightFlex = controller.getArea(1).flex;
    if (leftFlex == null || rightFlex == null || leftFlex + rightFlex <= 0) {
      return;
    }
    final ratio = leftFlex / (leftFlex + rightFlex);
    _syncedSplitRatio = ratio.clamp(minSplitRatio, maxSplitRatio);
    unawaited(ref.read(settingsProvider.notifier).setSplitRatio(_syncedSplitRatio!));
  }
}

/// Widths for the two-pane split: the list pane never gets narrower than a
/// readable card column, and the detail pane always keeps room for its
/// centred reading column.
const double paneDividerThickness = 24.0;
const double minPaneWidth = 320.0;
const double minDetailWidth = 420.0;

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
