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
import 'router.dart';
import 'session_cache_refresh.dart';

/// Root widget: owns theming (Light/Dark + reading scale) and the router.
class Mv2App extends ConsumerWidget {
  const Mv2App({super.key});

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

    return MaterialApp.router(
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
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
