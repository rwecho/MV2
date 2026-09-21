import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/network/web_cookie_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebCookieBridge.parseHeader', () {
    test('splits pairs and binds them to the v2ex domain', () {
      final cookies = WebCookieBridge.parseHeader(
        'PB3_SESSION="2|1:0|abc"; V2EX_LANG=enus',
      );
      expect(cookies, hasLength(2));
      expect(cookies[0].name, 'PB3_SESSION');
      expect(cookies[0].value, '"2|1:0|abc"');
      expect(cookies[0].domain, 'www.v2ex.com');
      expect(cookies[0].path, '/');
      expect(cookies[1].name, 'V2EX_LANG');
    });

    test('skips malformed pairs', () {
      final cookies = WebCookieBridge.parseHeader('=novalue; ok=fine; broken');
      expect(cookies.map((c) => c.name), <String>['ok']);
    });
  });

  group('WebCookieBridge.cookieHeader', () {
    test('returns the native header through the channel', () async {
      const channel = MethodChannel('mv2/web_cookies/test');
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getCookies');
        expect(call.arguments, <String, String>{'url': 'https://www.v2ex.com/'});
        return 'PB3_SESSION=xyz';
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final header = await WebCookieBridge(
        channel: channel,
      ).cookieHeader('https://www.v2ex.com/');
      expect(header, 'PB3_SESSION=xyz');
    });

    test('a missing platform side degrades to null', () async {
      // No handler registered → MissingPluginException → null.
      const channel = MethodChannel('mv2/web_cookies/missing');
      final header = await WebCookieBridge(
        channel: channel,
      ).cookieHeader('https://www.v2ex.com/');
      expect(header, isNull);
    });
  });
}
