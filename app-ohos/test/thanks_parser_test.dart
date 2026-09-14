import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/parser/thanks_parser.dart';

/// `/thank/*` answers `200` JSON — not `302` — so a successful 感谢 must not be
/// reported as a failure.
void main() {
  group('ThanksParser', () {
    test('{"success": true} is success', () {
      final result = ThanksParser.parse(
        '{"success":true,"once":123456,"message":""}',
      );
      expect(result.success, isTrue);
    });

    test('an empty 200 body is success', () {
      expect(ThanksParser.parse('').success, isTrue);
      expect(ThanksParser.parse('   ').success, isTrue);
    });

    test('{"success": false} carries the server message', () {
      final result = ThanksParser.parse('{"success":false,"message":"感谢过于频繁"}');
      expect(result.success, isFalse);
      expect(result.errors, <String>['感谢过于频繁']);
    });

    test('a failure without a message gets a generic one', () {
      final result = ThanksParser.parse('{"success":false}');
      expect(result.success, isFalse);
      expect(result.errors.single, isNotEmpty);
    });

    test('an HTML problem list still parses', () {
      final result = ThanksParser.parse(
        '<div class="problem"><ul><li>请先登录</li></ul></div>',
      );
      expect(result.success, isFalse);
      expect(result.errors, <String>['请先登录']);
    });
  });
}
