import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/deeplink/clipboard_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardProbe.changeCount', () {
    test('returns the native counter through the channel', () async {
      const channel = MethodChannel('mv2/clipboard/test');
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'changeCount');
        return 42;
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      expect(
        await ClipboardProbe(channel: channel).changeCount(),
        42,
      );
    });

    test('a negative counter (Android: no API) degrades to null', () async {
      const channel = MethodChannel('mv2/clipboard/negative');
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async => -1);
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      expect(
        await ClipboardProbe(channel: channel).changeCount(),
        isNull,
      );
    });

    test('a missing platform side degrades to null', () async {
      const channel = MethodChannel('mv2/clipboard/missing');
      expect(
        await ClipboardProbe(channel: channel).changeCount(),
        isNull,
      );
    });
  });

  group('ClipboardProbe.hasProbableWebURL', () {
    test('returns the native detection result', () async {
      const channel = MethodChannel('mv2/clipboard/detect-test');
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'hasProbableWebURL');
        return false;
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      expect(
        await ClipboardProbe(channel: channel).hasProbableWebURL(),
        isFalse,
      );
    });

    test('a missing platform side degrades to null (treated as possible)', ()
        async {
      const channel = MethodChannel('mv2/clipboard/detect-missing');
      expect(
        await ClipboardProbe(channel: channel).hasProbableWebURL(),
        isNull,
      );
    });
  });
}
