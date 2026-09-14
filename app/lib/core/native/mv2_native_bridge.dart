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
