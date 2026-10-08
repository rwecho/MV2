import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/notifications/application/notifications_providers.dart';
import '../../features/shell/application/chrome_actions.dart';
import '../../features/shell/application/shell_tabs.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../utils/scene_geometry.dart';
import 'mv2_floating_tab_bar.dart';
import 'mv2_trailing_chrome.dart';

/// Hosts the iPhone Duo's trailing edge chrome for the **whole window**.
///
/// Sits above the router (see `Mv2App.builder`) so the strip survives route
/// pushes — it is window chrome, exactly like the system status column that
/// shares it. Content is laid out beside the strip with the strip's inset
/// subtracted from its media padding, and descendants can read the measurement
/// back through [Mv2WindowChromeScope].
///
/// Devices without such a strip get their child untouched (no extra widget in
/// the layout path beyond the scope).
class Mv2WindowChromeHost extends ConsumerStatefulWidget {
  const Mv2WindowChromeHost({
    super.key,
    required this.navigatorKey,
    required this.router,
    required this.child,
  });

  /// Root navigator, so the strip's actions can open sheets and routes even
  /// though the host itself sits above the `Navigator` it wraps.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Watched for navigation: every route change drops the previous page's
  /// toolbar actions, and the page that lands republishes its own on the next
  /// frame. Clearing here (instead of in the page's `dispose`) keeps Riverpod
  /// out of `dispose`, where its container may already be gone.
  final GoRouter router;

  final Widget child;

  @override
  ConsumerState<Mv2WindowChromeHost> createState() =>
      _Mv2WindowChromeHostState();
}

class _Mv2WindowChromeHostState extends ConsumerState<Mv2WindowChromeHost> {
  /// Location the current page's actions were published for. GoRouter notifies
  /// several times per transition (animate, settle), so only a *different*
  /// location clears them — otherwise we would wipe what the landing page just
  /// published.
  late String _location = widget.router.state.uri.toString();

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRouteChanged);
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  void _onRouteChanged() {
    if (!mounted) return;
    final location = widget.router.state.uri.toString();
    if (location == _location) return;
    _location = location;
    ref.read(toolbarActionsProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final navigatorKey = widget.navigatorKey;
    final child = widget.child;
    final padding = MediaQuery.paddingOf(context);
    final stripWidth = mv2StripWidthFrom(padding);
    if (stripWidth <= 0) {
      return Mv2WindowChromeScope(
        stripWidth: 0,
        topInset: 0,
        child: child,
      );
    }

    final topInset = mv2RailTopInset(context, stripWidth);
    // The content must not reserve the strip again: it is a sibling now.
    final contentMedia = MediaQuery.of(context).copyWith(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      viewPadding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
    );
    final actionContext = navigatorKey.currentContext ?? context;

    return Mv2WindowChromeScope(
      stripWidth: stripWidth,
      topInset: topInset,
      child: ColoredBox(
        color: context.colors.background,
        child: Row(
          children: <Widget>[
            Expanded(
              child: MediaQuery(data: contentMedia, child: child),
            ),
            SizedBox(
              width: stripWidth,
              child: Mv2TrailingChrome(
                current: ref.watch(shellTabProvider),
                onSelect: (Mv2Tab tab) =>
                    selectShellTab(actionContext, ref, tab),
                notificationUnread: ref.watch(notificationUnreadProvider),
                topInset: topInset,
                bottomInset: padding.bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
