import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/core/parser/login_parser.dart';
import 'package:mv2/shared/models/login_form.dart';

String challenge(String once, {String error = ''}) =>
    '''
<form method="post" action="/2fa?next=/mission/daily">
<input type="hidden" name="once" value="$once">
<input type="hidden" name="next" value="/mission/daily">
<input type="text" name="otp" autocomplete="one-time-code">
</form>$error''';
HttpResult response(int status, {String body = '', String? location}) =>
    HttpResult(
      statusCode: status,
      body: body,
      headers: {
        if (location != null) 'location': [location],
      },
    );

class Client extends Mv2HttpClient {
  Client() : super(Dio(), CookieJar());
  final answers = <HttpResult>[];
  final gets = <String>[];
  final posts = <({String path, String? referer, Map<String, String> data})>[];
  @override
  Future<HttpResult> get(
    String path, {
    Map<String, dynamic>? query,
    String? referer,
    String? baseUrl,
    String? userAgent,
    PacePriority priority = PacePriority.userRead,
  }) async {
    gets.add(path);
    return answers.removeAt(0);
  }

  @override
  Future<HttpResult> postForm(
    String path, {
    required Map<String, String> data,
    String? referer,
    String? userAgent,
  }) async {
    posts.add((path: path, referer: referer, data: data));
    return answers.removeAt(0);
  }
}

void main() {
  const passwordForm = V2LoginForm(
    usernameFieldName: 'user',
    passwordFieldName: 'password',
    captchaFieldName: 'captcha',
    once: 'password-token',
    next: '/',
    captchaPath: '/_captcha',
  );

  test(
    'ordinary accounts complete password login without a two-factor prompt',
    () async {
      final client = Client()
        ..answers.addAll([
          response(302, location: '/'),
          response(200, body: '<html><body>Authenticated home</body></html>'),
        ]);
      final result = await RemoteV2exApi(client).login(
        form: passwordForm,
        username: 'member',
        password: 'secret',
        captcha: 'abcd',
      );
      expect(result.success, isTrue);
      expect(result.twoFactor, isFalse);
      expect(result.challenge, isNull);
      expect(client.gets, ['https://www.v2ex.com/']);
    },
  );

  test(
    'loads the challenge and submits its own token, input name and target',
    () async {
      final client = Client()
        ..answers.addAll([
          response(302, location: '/2fa?next=/mission/daily'),
          response(200, body: challenge('challenge-token')),
          response(302, location: '/mission/daily'),
        ]);
      final api = RemoteV2exApi(client);
      final first = await api.login(
        form: passwordForm,
        username: 'member',
        password: 'secret',
        captcha: 'abcd',
      );
      expect(first.success, isFalse);
      expect(first.twoFactor, isTrue);
      expect(
        client.gets.single,
        'https://www.v2ex.com/2fa?next=/mission/daily',
      );
      final second = await api.twoStep(form: first.challenge!, code: '123456');
      expect(second.success, isTrue);
      expect(client.posts.last.data, {
        'once': 'challenge-token',
        'next': '/mission/daily',
        'otp': '123456',
      });
      expect(client.posts.last.referer, client.posts.last.path);
    },
  );

  test(
    'follows next page redirect before discovering two-factor challenge',
    () async {
      final client = Client()
        ..answers.addAll([
          response(302, location: '/'),
          response(302, location: '/2fa?next=/'),
          response(200, body: challenge('indirect-token')),
        ]);
      final result = await RemoteV2exApi(client).login(
        form: passwordForm,
        username: 'member',
        password: 'secret',
        captcha: 'abcd',
      );
      expect(result.success, isFalse);
      expect(result.twoFactor, isTrue);
      expect(result.challenge!.fields['once'], 'indirect-token');
      expect(client.gets, [
        'https://www.v2ex.com/',
        'https://www.v2ex.com/2fa?next=/',
      ]);
    },
  );

  test(
    'incorrect OTP keeps the challenge and rotates its token for retry',
    () async {
      final client = Client()
        ..answers.add(
          response(
            200,
            body: challenge(
              'new-token',
              error: '<div class="problem"><ul><li>验证码不正确</li></ul></div>',
            ),
          ),
        );
      final form = LoginFormParser.parseTwoFactor(
        challenge('old-token'),
        path: '/2fa',
      )!;
      final result = await RemoteV2exApi(client)
          .twoStep(form: form, code: '000000');
      expect(result.success, isFalse);
      expect(result.requiresPassword, isFalse);
      expect(result.challenge!.fields['once'], 'new-token');
      expect(result.errors, ['验证码不正确']);
    },
  );

  test(
    'redirect to signin is an expired challenge, never login success',
    () async {
      final client = Client()
        ..answers.add(response(302, location: '/signin?next=/'));
      final result = await RemoteV2exApi(client).twoStep(
        form: LoginFormParser.parseTwoFactor(challenge('token'), path: '/2fa')!,
        code: '123456',
      );
      expect(result.success, isFalse);
      expect(result.requiresPassword, isTrue);
    },
  );

  test('a signin redirect after password submit is not success', () async {
    final client = Client()
      ..answers.add(response(302, location: '/signin/cooldown'));
    final result = await RemoteV2exApi(client).login(
      form: passwordForm,
      username: 'member',
      password: 'secret',
      captcha: 'abcd',
    );
    expect(result.success, isFalse);
  });

  test('rejects a challenge form posting credentials to another origin', () {
    expect(
      LoginFormParser.parseTwoFactor(
        challenge('token')
            .replaceFirst('action="/2fa', 'action="https://example.com/2fa'),
        path: '/2fa',
      ),
      isNull,
    );
  });
}
