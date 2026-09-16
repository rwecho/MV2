import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'v2ex_endpoints.dart';

/// Resolves the User-Agent presented on content-creating writes (reply, new
/// topic, append) — see the "write UAs" block in `V2exEndpoints` for why these
/// must differ from the read UA.
///
/// `Platform.isIOS` covers iPhone *and* iPad, so the shortest viewport edge —
/// Flutter's standard 600 dp adaptive breakpoint — separates them: iPads keep
/// an iPad Safari UA (`via iPad`), phones an iPhone one (`via iPhone`). Android
/// sends Chrome's reduced UA (`via Android`); other platforms send desktop
/// Chrome, which V2EX labels with nothing at all.
abstract final class V2exWriteUa {
  /// Shortest window edge in logical pixels. Writes only happen long after
  /// the shell has rendered, so the first view is always present.
  static double _shortestEdgeDp() {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return 0;
    final view = views.first;
    if (view.devicePixelRatio <= 0) return 0;
    return view.physicalSize.shortestSide / view.devicePixelRatio;
  }

  static const double _tabletBreakpointDp = 600;

  /// The UA for the next content write. Synchronous on purpose: device
  /// identity never changes mid-session and write call sites stay simple.
  static String resolveSync() {
    if (Platform.isIOS) {
      return _shortestEdgeDp() >= _tabletBreakpointDp
          // iPad Safari (`via iPad`).
          ? V2exEndpoints.userAgent
          : V2exEndpoints.iPhoneWriteUserAgent;
    }
    if (Platform.isAndroid) {
      return V2exEndpoints.androidWriteUserAgent();
    }
    return V2exEndpoints.desktopWriteUserAgent;
  }
}
