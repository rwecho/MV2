import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/deeplink/deep_link_listener.dart';
import '../../core/native/widget_sync.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../features/settings/application/settings_controller.dart';
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
