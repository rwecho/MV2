import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widget_snapshot.dart';

/// Dart half of the `mv2/native` channel (see `ios/Runner/MV2NativeBridge.swift`).
///
/// Everything here is **best-effort**: on Android, in tests, or on an iOS build
/// without the native side yet, the channel is simply missing and the calls
/// become no-ops. A widget must never be able to break the app.
class Mv2NativeBridge {
  const Mv2NativeBridge({this.channel = _defaultChannel});

  /// Keep in sync with `MV2NativeBridge.channelName` on the iOS side.
  static const MethodChannel _defaultChannel = MethodChannel('mv2/native');

  /// Injectable so widget-bridge tests can substitute a fake messenger.
  final MethodChannel channel;

  /// Publishes the widget payload to the shared App Group container.
  Future<void> setWidgetSnapshot(Mv2WidgetSnapshot snapshot) =>
      _invoke('setWidgetSnapshot', snapshot.toJson());

  Future<void> reloadWidgets() => _invoke('reloadWidgets');

  /// The quick action tapped before Dart was listening (cold launch), if any.
  Future<String?> consumePendingQuickAction() async {
    try {
      final route = await channel.invokeMethod<String>(
        'consumePendingQuickAction',
      );
      return (route == null || route.isEmpty) ? null : route;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Receives quick actions tapped while the app is running.
  void onQuickAction(void Function(String route) handler) {
    channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'quickAction') return null;
      final arguments = call.arguments;
      final route = arguments is Map ? arguments['route'] as String? : null;
      if (route != null && route.isNotEmpty) handler(route);
      return null;
    });
  }

  /// UIKit `horizontalSizeClass` ("compact" / "regular" / "unspecified").
  ///
  /// Apple 折叠屏适配信号：普通 iPhone（含横屏）恒为 compact，iPhone Duo
  /// 展开内屏为 regular。非 iOS（Android / 桌面 / 测试）没有此 trait，
  /// 通道缺失时返回 `null`，布局回退到纯宽度断点（现状不变）。
  Future<String?> horizontalSizeClass() async {
    try {
      return await channel.invokeMethod<String>('horizontalSizeClass');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Window-scene geometry: where the system draws its status bar and how much
  /// safe area the window keeps (see `ui/utils/scene_geometry.dart`).
  ///
  /// Flutter's own channel for this is `MediaQuery.displayFeaturesOf` (the
  /// engine is meant to report the Duo's reserved edge strip as a
  /// `DisplayFeatureType.cutout` — flutter/flutter#193025), but the engine in
  /// Flutter 3.47.3 reports `displayFeatures: []` on the Duo, so the native side
  /// supplies it until we upgrade. Returns `null` when the channel is missing
  /// or answers nothing usable.
  Future<Map<Object?, Object?>?> uiGeometry() async {
    try {
      return await channel.invokeMapMethod<Object?, Object?>('uiGeometry');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No native side (Android / tests) — nothing to update.
    } on PlatformException {
      // Widget refreshes are decorative; swallow and keep the app honest.
    }
  }
}

final nativeBridgeProvider = Provider<Mv2NativeBridge>(
  (ref) => const Mv2NativeBridge(),
);
