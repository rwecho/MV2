import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/scene_geometry.dart';

/// Window-level chrome scope.
///
/// The Duo's trailing bar now comes from `adaptive_platform_ui`'s fixed
/// toolbar chrome (installed in `Mv2App.builder`), which overlays its band on
/// the edge the system reserves. This host therefore no longer reserves
/// anything: it keeps the scope (so descendants can query the strip) and the
/// route listener that drops a page's toolbar actions when the route changes.
class Mv2WindowChromeHost extends ConsumerStatefulWidget {
  const Mv2WindowChromeHost({
    super.key,
    required this.navigatorKey,
    required this.router,
    required this.child,
  });

  /// Root navigator, kept for the actions the chrome still drives.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Watched for navigation: every route change clears the previous page's
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
  @override
  Widget build(BuildContext context) => Mv2WindowChromeScope(
    stripWidth: 0,
    topInset: 0,
    child: widget.child,
  );
}
