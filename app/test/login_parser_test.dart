import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/parser/login_parser.dart';

/// `signin_real.html` is the real `/signin?next=/` form captured on
/// 2026-09-11 (trimmed to the `<form>`), which is why the credential field
/// names look like random hashes — V2EX randomises them on every render.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('LoginFormParser', () {
    test('reads the randomised field names, once and captcha URL', () {
      final form = LoginFormParser.parse(fixture('signin_real.html'));

      expect(form, isNotNull);
      final parsed = form!;

      // Three distinct hash-named inputs: username, password, captcha.
      expect(parsed.usernameFieldName, hasLength(64));
      expect(parsed.passwordFieldName, hasLength(64));
      expect(parsed.captchaFieldName, hasLength(64));
      expect(<String>{
        parsed.usernameFieldName,
        parsed.passwordFieldName,
        parsed.captchaFieldName,
      }, hasLength(3));

      expect(parsed.once, '84014');
      expect(parsed.next, '/');
      expect(parsed.captchaPath, 'https://www.v2ex.com/_captcha');
    });

    test('returns null when the page has no usable login form', () {
      expect(LoginFormParser.parse('<html><body>nope</body></html>'), isNull);
    });

    test('parses V2EX error messages', () {
      const html = '''
        <div class="problem">
          <ul>
            <li>你输入的验证码不正确</li>
            <li>请重新输入</li>
          </ul>
        </div>
      ''';

      expect(LoginFormParser.parseErrors(html), <String>[
        '你输入的验证码不正确',
        '请重新输入',
      ]);
    });

    test('detects the 2FA redirect', () {
      expect(LoginFormParser.isTwoFactorRedirect('/2fa?next=/'), isTrue);
      expect(LoginFormParser.isTwoFactorRedirect('/'), isFalse);
      expect(LoginFormParser.isTwoFactorRedirect(null), isFalse);
    });
  });
}
