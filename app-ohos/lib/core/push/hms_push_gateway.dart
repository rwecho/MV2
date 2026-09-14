import 'dart:async';

import 'package:flutter/services.dart';

import 'push_gateway.dart';

/// [Mv2PushGateway] backed by HarmonyOS **Push Kit** (HMS).
///
/// The native half lives in
/// `ohos/entry/src/main/ets/push/HmsPushBridge.ets` and is reached through two
/// channels:
///
/// * `mv2/push` — request/response calls: `isConfigured`, `getToken`,
///   `requestPermission`, `initialOpened`;
/// * `mv2/push/events` — a stream of `{type, ...}` maps carrying `tokenUpdate`,
///   foreground `message` and notification-tap `opened` events.
///
/// Nothing here throws. A build without AppGallery Connect configuration (or a
/// widget test, where the channel is missing) simply leaves push unavailable,
/// which is exactly what [Mv2PushGateway] promises its callers.
class HmsPushGateway implements Mv2PushGateway {
  HmsPushGateway({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel(methodChannelName),
      _events = events ?? const EventChannel(eventChannelName);

  /// Keep in sync with `HmsPushBridge.METHOD_CHANNEL` in ArkTS.
  static const String methodChannelName = 'mv2/push';

  /// Keep in sync with `HmsPushBridge.EVENT_CHANNEL` in ArkTS.
  static const String eventChannelName = 'mv2/push/events';

  final MethodChannel _methods;
  final EventChannel _events;

  bool _available = false;
  bool _listening = false;
  String? _token;
  StreamSubscription<Object?>? _eventsSubscription;

  final StreamController<String> _tokenRefreshes =
      StreamController<String>.broadcast();
  final StreamController<Map<String, Object?>> _opened =
      StreamController<Map<String, Object?>>.broadcast();
  final StreamController<Map<String, Object?>> _foreground =
      StreamController<Map<String, Object?>>.broadcast();

  @override
  bool get isAvailable => _available;

  @override
  Future<void> initialize() async {
    if (_available) return;
    try {
      // The native side reports whether the AGC `client_id` metadata in
      // module.json5 left its placeholder behind. No real AppGallery Connect
      // project means push off, without ever calling into Push Kit.
      final configured =
          await _methods.invokeMethod<bool>('isConfigured') ?? false;
      if (!configured) return;

      // A successful token request is the only proof the device is actually
      // allowed to use Push Kit, so availability waits for it.
      final token = await _methods.invokeMethod<String>('getToken');
      if (token == null || token.isEmpty) return;

      _token = token;
      _listen();
      _available = true;
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    } catch (_) {
      _available = false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_available) return false;
    try {
      return await _methods.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> token() async {
    if (!_available) return null;
    final cached = _token;
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final token = await _methods.invokeMethod<String>('getToken');
      if (token == null || token.isEmpty) return null;
      _token = token;
      return token;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> tokenRefreshes() =>
      _available ? _tokenRefreshes.stream : const Stream<String>.empty();

  @override
  Stream<Map<String, Object?>> opened() =>
      _available ? _opened.stream : const Stream<Map<String, Object?>>.empty();

  @override
  Future<Map<String, Object?>?> initialOpened() async {
    if (!_available) return null;
    try {
      return _map(await _methods.invokeMethod<Object?>('initialOpened'));
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Map<String, Object?>> foreground() => _available
      ? _foreground.stream
      : const Stream<Map<String, Object?>>.empty();

  /// Detaches from the platform channels. Safe to call more than once.
  Future<void> dispose() async {
    _available = false;
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    if (!_tokenRefreshes.isClosed) await _tokenRefreshes.close();
    if (!_opened.isClosed) await _opened.close();
    if (!_foreground.isClosed) await _foreground.close();
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    _eventsSubscription = _events
        .receiveBroadcastStream()
        // A malformed platform event must not take the app down.
        .listen(_onEvent, onError: (Object _) {});
  }

  void _onEvent(Object? event) {
    final envelope = _map(event);
    if (envelope == null) return;

    final type = envelope['type'];
    if (type == 'token') {
      final token = envelope['token'];
      if (token is String && token.isNotEmpty) {
        _token = token;
        if (!_tokenRefreshes.isClosed) _tokenRefreshes.add(token);
      }
      return;
    }

    if (type == 'message') {
      final data = _map(envelope['data']);
      if (data != null && !_foreground.isClosed) _foreground.add(data);
      return;
    }

    if (type == 'opened') {
      final data = _map(envelope['data']);
      if (data != null && !_opened.isClosed) _opened.add(data);
    }
  }

  /// Narrows a platform value to the `String`-keyed map the service consumes.
  static Map<String, Object?>? _map(Object? value) {
    if (value is! Map) return null;
    final result = <String, Object?>{};
    value.forEach((key, item) {
      if (key is String) result[key] = item;
    });
    return result.isEmpty ? null : result;
  }
}
