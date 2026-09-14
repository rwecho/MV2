import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/tokens/mv2_motion.dart';
import '../../../ui/components/mv2_floating_tab_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_session.dart';
import '../../composer/presentation/composer_sheets.dart';
import '../../notifications/application/notifications_providers.dart';
import '../application/shell_chrome.dart';

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

    return Stack(
      children: <Widget>[
        widget.navigationShell,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSlide(
            // Slide the whole padded bar (bar + safe area) below the viewport.
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
    );
  }
}
