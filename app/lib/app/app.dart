import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/deeplink/deep_link_listener.dart';
import '../../core/telemetry/mv2_analytics.dart';
import '../../core/telemetry/mv2_telemetry.dart';
import '../../core/native/widget_sync.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/settings/application/settings_controller.dart';
import '../../ui/utils/mv2_breakpoints.dart';
import '../../ui/primitives/mv2_shad_theme.dart';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:foldable/foldable.dart';

import '../../ui/components/mv2_window_chrome.dart';
import '../../ui/utils/scene_sync.dart';
import 'router.dart';
import 'session_cache_refresh.dart';

/// Root widget: owns theming (Light/Dark + reading scale) and the router.
class Mv2App extends ConsumerWidget {
  const Mv2App({super.key, this.debugFoldable, this.debugFold});

  /// Synthetic fold snapshots for tests: the platform channel that normally
  /// carries them does not exist in the test binding.
  final Stream<FoldableData>? debugFoldable;

  /// Same snapshot for the fixed toolbar chrome, which reads the fold on its
  /// own. Test-only, mirroring the package's own `debugFold` seam.
  final FoldableData? debugFold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Keeps session-scoped caches honest across sign-in/sign-out; watching it at
    // the root means it runs regardless of the current route.
    ref.watch(sessionCacheRefreshProvider);
    // Keeps the iOS Home Screen widget's snapshot in step with the app.
    ref.watch(widgetSyncProvider);
    // Theme context on every crash/non-fatal report: 颜色 reports are only
    // diagnosable against what the app actually applied.
    Mv2Telemetry.setThemeContext(colorMode: settings.colorMode.name);
    // 用户属性(boot + 每次设置/登录态变化): 群体交叉分析的分析维度。
    // watch authControllerProvider 让登录/登出自动重新同步 user_id 与 signed_in。
    final auth = ref.watch(authControllerProvider);
    Mv2Analytics.syncUserId(memberId: auth.value?.memberId);
    Mv2Analytics.syncUserProperties(
      colorMode: settings.colorMode.name,
      fontSize: settings.fontSize.name,
      contentWidth: settings.contentWidth.name,
      linkOpenMode: settings.openLinkMode.name,
      pushEnabled: '${settings.pushEnabled}',
      replySort: settings.replySort.name,
      signedIn: '${auth.value?.isSignedIn ?? false}',
      layout: mv2IsTwoPane(context) ? 'tablet' : 'phone',
    );
    // Firebase 就绪后重建一次,boot 阶段被丢弃的用户属性借此补齐。
    ref.watch(telemetryReadyProvider);

    // Fold geometry (hinge posture, fold / camera reserved regions) bridged
    // from UIKit; the trailing chrome reads it through [DuoMediaQuery]. The
    // MediaQuery bridge stays off: publishing the fold would split every
    // Material dialog and sheet (see the package README).
    return FoldableProvider(
      debugData: debugFoldable,
      child: MaterialApp.router(
        title: 'MV2',
        debugShowCheckedModeBanner: false,
        theme: Mv2ThemeData.light(textScale: settings.fontSize.scale),
        darkTheme: Mv2ThemeData.dark(textScale: settings.fontSize.scale),
        themeMode: settings.themeMode,
        routerConfig: ref.watch(routerProvider),
        // The listener sits above the router, not inside the tab shell: a cold
        // start straight into `/topic/123` (an `mv2://` link) never builds the
        // shell, and push registration plus notification taps must still work on
        // that launch.
        builder: (context, child) => Mv2ShadScope(
          child: Mv2DeepLinkListener(
            child: Mv2SceneSync(
              // Fixed toolbar chrome from `adaptive_platform_ui`: it lives
              // above the navigator, owns the registry every AdaptiveScaffold
              // publishes its app bar to, and draws the one persistent bar
              // (plus the Duo's trailing capsule bar) instead of a bar per
              // route. Pages migrate onto it one by one.
              child: AdaptiveToolbarHost(
                // ignore: invalid_use_of_visible_for_testing_member
                debugFold: debugFold,
                child: Mv2WindowChromeHost(
                  navigatorKey: rootNavigatorKey,
                  router: ref.watch(routerProvider),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
