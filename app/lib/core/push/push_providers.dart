import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/application/settings_controller.dart';
import 'push_gateway.dart';
import 'push_service.dart';

/// The push SDK, swappable in tests (`overrideWithValue`).
final pushGatewayProvider = Provider<Mv2PushGateway>(
  (ref) => FirebasePushGateway(),
);

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
