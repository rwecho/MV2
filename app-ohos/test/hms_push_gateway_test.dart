import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/push/hms_push_gateway.dart';

/// Platform-channel names the gateway talks to (kept in sync with the ArkTS
/// `HmsPushBridge`).
const MethodChannel _methods = MethodChannel(HmsPushGateway.methodChannelName);
const EventChannel _events = EventChannel(HmsPushGateway.eventChannelName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;
  late bool configured;
  late Object? tokenResult;
  late bool permission;
  late Map<String, Object?>? coldStartPayload;
  MockStreamHandlerEventSink? sink;

  void installHandlers() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methods, (MethodCall call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'isConfigured':
              return configured;
            case 'getToken':
              final result = tokenResult;
              if (result is PlatformException) throw result;
              return result;
            case 'requestPermission':
              return permission;
            case 'initialOpened':
              return coldStartPayload;
            default:
              return null;
          }
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          _events,
          MockStreamHandler.inline(
            onListen: (Object? arguments, MockStreamHandlerEventSink events) =>
                sink = events,
            onCancel: (Object? arguments) => sink = null,
          ),
        );
  }

  setUp(() {
    calls = <String>[];
    configured = true;
    tokenResult = 'hms-token-1';
    permission = true;
    coldStartPayload = null;
    sink = null;
    installHandlers();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_methods, null)
      ..setMockStreamHandler(_events, null);
  });

  test('is unavailable when the AGC client_id is not configured', () async {
    configured = false;
    final gateway = HmsPushGateway();
    await gateway.initialize();

    expect(gateway.isAvailable, isFalse);
    // A missing AppGallery Connect project must not even ask for a token.
    expect(calls, isNot(contains('getToken')));
    expect(await gateway.token(), isNull);
    await gateway.dispose();
  });

  test('is unavailable when getToken fails, without throwing', () async {
    tokenResult = PlatformException(code: 'hms-token-failed');
    final gateway = HmsPushGateway();
    await gateway.initialize();

    expect(gateway.isAvailable, isFalse);
    expect(await gateway.token(), isNull);
    await gateway.dispose();
  });

  test('becomes available only after a token is obtained', () async {
    final gateway = HmsPushGateway();
    await gateway.initialize();

    expect(gateway.isAvailable, isTrue);
    expect(calls, contains('isConfigured'));
    expect(calls, contains('getToken'));
    expect(await gateway.token(), 'hms-token-1');

    // The token is cached: a second read must not hit the platform again.
    final getTokenCalls = calls.where((String m) => m == 'getToken').length;
    await gateway.token();
    expect(calls.where((String m) => m == 'getToken').length, getTokenCalls);
    await gateway.dispose();
  });

  test('requestPermission is false while unavailable and forwarded when up',
      () async {
    configured = false;
    final off = HmsPushGateway();
    await off.initialize();
    expect(await off.requestPermission(), isFalse);
    expect(calls, isNot(contains('requestPermission')));
    await off.dispose();

    permission = false;
    configured = true;
    final on = HmsPushGateway();
    await on.initialize();
    expect(await on.requestPermission(), isFalse);
    expect(calls, contains('requestPermission'));
    await on.dispose();
  });

  test('initialOpened returns the buffered cold-start payload once', () async {
    coldStartPayload = <String, Object?>{'link': '/t/123', 'topicId': '123'};
    final gateway = HmsPushGateway();
    await gateway.initialize();

    final payload = await gateway.initialOpened();
    expect(payload, <String, Object?>{'link': '/t/123', 'topicId': '123'});
    await gateway.dispose();
  });

  test('routes tokenUpdate, message and opened events to the right streams',
      () async {
    final gateway = HmsPushGateway();
    await gateway.initialize();
    expect(sink, isNotNull);

    final tokens = <String>[];
    final foreground = <Map<String, Object?>>[];
    final opened = <Map<String, Object?>>[];
    gateway.tokenRefreshes().listen(tokens.add);
    gateway.foreground().listen(foreground.add);
    gateway.opened().listen(opened.add);

    sink!.success(<String, Object?>{'type': 'token', 'token': 'hms-token-2'});
    sink!.success(<String, Object?>{
      'type': 'message',
      'data': <String, Object?>{'link': '/t/1'},
    });
    sink!.success(<String, Object?>{
      'type': 'opened',
      'data': <String, Object?>{'link': '/t/2', 'topicId': '2'},
    });
    await pumpEventQueue();

    expect(tokens, <String>['hms-token-2']);
    expect(foreground.single['link'], '/t/1');
    expect(opened.single['topicId'], '2');
    await gateway.dispose();
  });

  test('a missing native side degrades to unavailable, never throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_methods, null)
      ..setMockStreamHandler(_events, null);

    final gateway = HmsPushGateway();
    await gateway.initialize();

    expect(gateway.isAvailable, isFalse);
    expect(await gateway.token(), isNull);
    await gateway.dispose();
  });
}
