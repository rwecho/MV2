import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/auth/presentation/login_page.dart';
import 'package:mv2/shared/models/login_form.dart';
import 'support/fixture_api.dart';

/// A 1x1 transparent PNG so `Image.memory` can actually decode in the test.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// Serves a **new** form render (new `once`, new field names) on every
/// `loginForm()` call, exactly like the live site, and rejects the first submit
/// the way a wrong captcha does.
class _RotatingLoginApi extends FixtureV2exApi {
  _RotatingLoginApi() : super(latency: Duration.zero);

  int formRenders = 0;
  int captchaFetches = 0;
  final List<String> submittedOnce = <String>[];
  final List<String> capturedOnceParam = <String>[];

  @override
  Future<V2LoginForm?> loginForm() async {
    formRenders += 1;
    return V2LoginForm(
      usernameFieldName: 'user-$formRenders',
      passwordFieldName: 'pass-$formRenders',
      captchaFieldName: 'captcha-$formRenders',
      once: 'once-$formRenders',
      next: '/',
      captchaPath: 'https://www.v2ex.com/_captcha',
    );
  }

  @override
  Future<List<int>> captchaImage(String captchaPath, {String? once}) async {
    captchaFetches += 1;
    capturedOnceParam.add(once ?? '');
    return _onePixelPng;
  }

  @override
  Future<V2LoginResult> login({
    required V2LoginForm form,
    required String username,
    required String password,
    required String captcha,
  }) async {
    submittedOnce.add(form.once);
    if (submittedOnce.length == 1) {
      // What a real wrong-captcha POST answers: the captcha complaint *and*,
      // once the page has been re-rendered, a stale-token rejection if the old
      // `once` is sent again.
      return const V2LoginResult(
        success: false,
        errors: <String>['输入的验证码不正确', 'CSRF 失效，请重新提交'],
      );
    }
    return const V2LoginResult(
      success: false,
      errors: <String>['输入的验证码不正确'],
    );
  }
}

void main() {
  // The credential + captcha form plus the submit button is taller than the
  // default 800x600 test surface; give it room so the button is hittable.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<_RotatingLoginApi> pumpLogin(WidgetTester tester) async {
    useTallSurface(tester);
    final api = _RotatingLoginApi();
    final container = ProviderContainer(
      overrides: [v2exApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  Future<void> fillAndSubmit(WidgetTester tester) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'someone');
    await tester.enterText(fields.at(1), 'secret');
    await tester.enterText(fields.at(2), 'zzzz');
    await tester.pump();
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
  }

  testWidgets('a failed submit re-scrapes the form so the retry uses a fresh '
      'once', (tester) async {
    final api = await pumpLogin(tester);

    // Initial load: form render #1 + its captcha.
    expect(api.formRenders, 1);
    expect(api.captchaFetches, 1);

    await fillAndSubmit(tester);

    // The failure must have re-scraped the whole form, not only the image.
    expect(api.submittedOnce, <String>['once-1']);
    expect(api.formRenders, 2);
    expect(api.captchaFetches, 2);
    // The captcha that was re-fetched belongs to the *new* render.
    expect(api.capturedOnceParam.last, 'once-2');

    // The V2EX reason stays visible, with the opaque CSRF text translated.
    expect(find.text('输入的验证码不正确'), findsOneWidget);
    expect(find.text('登录令牌已过期，请重试'), findsOneWidget);

    // The refresh cleared the captcha input, so the user re-enters it.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(2), 'yyyy');
    await tester.pump();
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    // This is the regression itself: the second POST must carry `once-2`.
    expect(api.submittedOnce, <String>['once-1', 'once-2']);
    expect(find.text('CSRF 失效，请重新提交'), findsNothing);
    expect(find.text('登录令牌已过期，请重试'), findsNothing);
    expect(find.text('输入的验证码不正确'), findsOneWidget);
  });

  testWidgets('an empty-error failure still shows an actionable message', (
    tester,
  ) async {
    useTallSurface(tester);
    final api = _EmptyErrorLoginApi();
    final container = ProviderContainer(
      overrides: [v2exApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await fillAndSubmit(tester);

    expect(find.text('登录失败，请检查账号、密码与验证码。'), findsOneWidget);
  });

  testWidgets('a sign-in rate limit is named in the title, not hidden as a '
      'generic form failure', (tester) async {
    useTallSurface(tester);
    final container = ProviderContainer(
      overrides: [v2exApiProvider.overrideWithValue(_CooldownLoginApi())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // V2EX answers `302 -> /signin/cooldown`; the page must say so instead of
    // showing a generic 无法加载登录表单.
    expect(find.text('登录尝试过于频繁'), findsOneWidget);
    expect(find.text('无法加载登录表单'), findsNothing);
    expect(find.text('用浏览器打开'), findsOneWidget);
  });
}

/// A wrong-credential rejection with no scraped `div.problem` text.
class _EmptyErrorLoginApi extends FixtureV2exApi {
  _EmptyErrorLoginApi() : super(latency: Duration.zero);

  @override
  Future<V2LoginForm?> loginForm() async => const V2LoginForm(
    usernameFieldName: 'u',
    passwordFieldName: 'p',
    captchaFieldName: 'c',
    once: 'once-1',
    next: '/',
    captchaPath: 'https://www.v2ex.com/_captcha',
  );

  @override
  Future<List<int>> captchaImage(String captchaPath, {String? once}) async =>
      _onePixelPng;

  @override
  Future<V2LoginResult> login({
    required V2LoginForm form,
    required String username,
    required String password,
    required String captcha,
  }) async => const V2LoginResult(success: false);
}

/// V2EX refuses `/signin` for a while after too many attempts.
class _CooldownLoginApi extends FixtureV2exApi {
  _CooldownLoginApi() : super(latency: Duration.zero);

  @override
  Future<V2LoginForm?> loginForm() async =>
      throw const RateLimitFailure(message: '登录尝试过于频繁，请稍后再试。');
}
