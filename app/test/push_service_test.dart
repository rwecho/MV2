import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/push/push_gateway.dart';
import 'package:mv2/core/push/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stand-in for `FirebasePushGateway`: no plugin, no platform channels.
class FakePushGateway implements Mv2PushGateway {
  FakePushGateway({
    this.available = true,
    this.permissionGranted = true,
    this.fcmToken = 'tok-1',
  });

  bool available;
  bool permissionGranted;
  String? fcmToken;

  int permissionRequests = 0;
  int initializeCalls = 0;

  /// When set, [initialize] blocks until it completes — used to interleave a
  /// registration with a still-running startup.
  Completer<void>? initializeGate;

  final StreamController<String> _tokenRefreshes =
      StreamController<String>.broadcast();
  final StreamController<Map<String, Object?>> _opened =
      StreamController<Map<String, Object?>>.broadcast();
  final StreamController<Map<String, Object?>> _foreground =
      StreamController<Map<String, Object?>>.broadcast();

  @override
  bool get isAvailable => available && _initialized;

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    await initializeGate?.future;
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted && available;
  }

  @override
  Future<String?> token() async => available ? fcmToken : null;

  @override
  Stream<String> tokenRefreshes() => _tokenRefreshes.stream;

  @override
  Stream<Map<String, Object?>> opened() => _opened.stream;

  @override
  Future<Map<String, Object?>?> initialOpened() async => null;

  @override
  Stream<Map<String, Object?>> foreground() => _foreground.stream;

  void rotateToken(String value) {
    fcmToken = value;
    _tokenRefreshes.add(value);
  }

  Future<void> dispose() async {
    await _tokenRefreshes.close();
    await _opened.close();
    await _foreground.close();
  }
}

/// Records every POST and answers with a scripted status.
class RecordingPost {
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
  final List<String> urls = <String>[];
  bool accepted = true;

  Future<bool> call(String url, Map<String, Object?> body) async {
    urls.add(url);
    calls.add(body);
    return accepted;
  }

  List<String> get paths =>
      urls.map((url) => Uri.parse(url).path).toList(growable: false);
}

const String _feed =
    'https://www.v2ex.com/feed/notifications.xml?once=abc123';

void main() {
  late FakePushGateway gateway;
  late RecordingPost post;

  Mv2PushService buildService({bool enabled = true}) => Mv2PushService(
    pushGateway: gateway,
    isEnabled: () => enabled,
    post: post.call,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    gateway = FakePushGateway();
    post = RecordingPost();
  });

  group('Mv2PushService.register', () {
    test('posts the device token and feed URL once, then de-duplicates', () async {
      final service = buildService();

      await service.register(feedUrl: _feed);
      expect(post.paths, <String>['/register']);
      expect(post.calls.single['feedUrl'], _feed);
      expect(post.calls.single['fcmToken'], 'tok-1');
      expect(post.calls.single['deviceType'], isA<String>());
      expect(post.calls.single['deviceType'], isNotEmpty);

      // Reopening the notifications page must not re-POST the same pair.
      await service.register(feedUrl: _feed);
      expect(post.calls, hasLength(1));
    });

    test('a register racing with startup still sees a ready gateway', () async {
      // The shell calls `start()` and the notifications page calls `register()`
      // from the same frame; register must await the in-flight initialisation
      // instead of observing "not available" and bailing out.
      gateway.initializeGate = Completer<void>();
      final service = buildService();

      final starting = service.start();
      final registering = service.register(feedUrl: _feed);
      gateway.initializeGate!.complete();

      await starting;
      await registering;

      expect(post.calls, hasLength(1));
      expect(gateway.initializeCalls, 1);
    });

    test('re-registers when the account (feed URL) changes', () async {
      final service = buildService();
      await service.register(feedUrl: _feed);

      await service.register(
        feedUrl: 'https://www.v2ex.com/feed/notifications.xml?once=other',
      );

      expect(post.calls, hasLength(2));
      expect(post.calls.last['feedUrl'], contains('once=other'));
    });

    test('re-registers on token rotation using the remembered feed URL', () async {
      final service = buildService();
      await service.start();
      await service.register(feedUrl: _feed);
      expect(post.calls, hasLength(1));

      gateway.rotateToken('tok-2');
      await pumpEventQueue();

      expect(post.calls, hasLength(2));
      expect(post.calls.last['fcmToken'], 'tok-2');
      expect(post.calls.last['feedUrl'], _feed);
    });

    test('does nothing while 推送通知 is off', () async {
      final service = buildService(enabled: false);
      await service.register(feedUrl: _feed);
      expect(post.calls, isEmpty);
      expect(gateway.permissionRequests, 0);
    });

    test('does nothing without a feed URL (page never visited)', () async {
      final service = buildService();
      await service.register();
      expect(post.calls, isEmpty);
    });

    test('does nothing when permission is denied', () async {
      gateway.permissionGranted = false;
      final service = buildService();
      await service.register(feedUrl: _feed);
      expect(post.calls, isEmpty);
    });

    test('rejects a feed URL that is not a v2ex feed', () async {
      final service = buildService();
      await service.register(feedUrl: 'https://evil.example/feed/x.xml');
      await service.register(feedUrl: 'https://www.v2ex.com/t/123');
      expect(post.calls, isEmpty);
    });

    test('stays silent when the worker rejects the registration', () async {
      post.accepted = false;
      final service = buildService();
      await service.register(feedUrl: _feed);
      expect(post.calls, hasLength(1));

      // A rejected registration must not be remembered as successful.
      await service.register(feedUrl: _feed);
      expect(post.calls, hasLength(2));
    });

    test('a cold start does not re-POST an unchanged registration', () async {
      final first = buildService();
      await first.register(feedUrl: _feed);

      // New process: no feedUrl argument, only what was persisted. The worker
      // already knows this (token, feed) pair, so there is nothing to send.
      post.calls.clear();
      final second = buildService();
      await second.register();

      expect(post.calls, isEmpty);
    });
  });

  group('Mv2PushService.unregister', () {
    test('drops the device server-side and locally', () async {
      final service = buildService();
      await service.register(feedUrl: _feed);

      await service.unregister();

      expect(post.paths.last, '/unregister');
      expect(post.calls.last['fcmToken'], 'tok-1');

      // The opt-out is remembered: re-registering now needs the feed again.
      post.calls.clear();
      await service.register();
      expect(post.calls, isEmpty);
    });
  });
}
