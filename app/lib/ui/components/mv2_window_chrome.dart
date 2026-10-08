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

    final side = mv2DuoBarSideOf(context);
    if (side == null) {
      return Mv2WindowChromeScope(stripWidth: 0, topInset: 0, child: child);
    }

    final padding = MediaQuery.paddingOf(context);
    final stripWidth = mv2DuoStripWidthOf(context);
    final bandWidth = mv2DuoBandWidthOf(context);
    final insets = mv2DuoBarInsetsOf(context);
    final actionContext = navigatorKey.currentContext ?? context;
    final onRight = side == Mv2DuoBarSide.right;

    // The bar overlays the content by the band's inward inset (12pt), exactly
    // as the system's own controls do: the strip itself is subtracted from the
    // content, the bezel inset is not.
    final contentMedia = MediaQuery.of(context).copyWith(
      padding: EdgeInsets.only(
        top: padding.top,
        bottom: padding.bottom,
        left: onRight ? padding.left : 0,
        right: onRight ? 0 : padding.right,
      ),
      viewPadding: EdgeInsets.only(
        top: padding.top,
        bottom: padding.bottom,
        left: onRight ? padding.left : 0,
        right: onRight ? 0 : padding.right,
      ),
    );

    return Mv2WindowChromeScope(
      stripWidth: stripWidth,
      topInset: insets.top,
      child: ColoredBox(
        color: context.colors.background,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Padding(
                padding: onRight
                    ? EdgeInsets.only(right: stripWidth)
                    : EdgeInsets.only(left: stripWidth),
                child: MediaQuery(data: contentMedia, child: child),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              width: bandWidth,
              right: onRight ? 0 : null,
              left: onRight ? null : 0,
              child: Mv2TrailingChrome(
                current: ref.watch(shellTabProvider),
                onSelect: (Mv2Tab tab) =>
                    selectShellTab(actionContext, ref, tab),
                notificationUnread: ref.watch(notificationUnreadProvider),
                topInset: insets.top,
                bottomInset: insets.bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
