import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/application/settings_controller.dart';
import 'hms_push_gateway.dart';
import 'push_gateway.dart';
import 'push_service.dart';

/// The push SDK, swappable in tests (`overrideWithValue`).
///
/// HarmonyOS has no Firebase SDK, so it talks to HMS Push Kit through the
/// `mv2/push` platform channel; every other platform keeps Firebase. The
/// gateway is a drop-in [Mv2PushGateway], so [Mv2PushService] and the UI are
/// unchanged either way.
final pushGatewayProvider = Provider<Mv2PushGateway>((ref) {
  if (defaultTargetPlatform == TargetPlatform.ohos) {
    return HmsPushGateway();
  }
  return FirebasePushGateway();
});

/// Device registration against the MV2 push worker.
///
/// The 推送通知 setting is read through a callback rather than `watch`, so
/// flipping the switch does not rebuild the service (and tear down its
/// subscriptions) — the next [Mv2PushService.register] just sees the new value.
final pushServiceProvider = Provider<Mv2PushService>((ref) {
  final service = Mv2PushService(
    pushGateway: ref.watch(pushGatewayProvider),
    isEnabled: () => ref.read(settingsProvider).pushEnabled,
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
