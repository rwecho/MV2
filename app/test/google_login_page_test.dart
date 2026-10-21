import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/network/web_cookie_bridge.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/auth/domain/auth_session.dart';
import 'package:mv2/features/auth/presentation/google_login_page.dart';
import 'package:mv2/features/auth/presentation/login_page.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/login_form.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/fixture_api.dart';

class _WebPlatform extends WebViewPlatform {
  late _Web web;
  late _Delegate delegate;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams p,
  ) => web = _Web(p);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams p,
  ) => delegate = _Delegate(p);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams p,
  ) => _View(p);
  void finish(String url) {
    web.url = url;
    delegate.progress(100);
    delegate.finished(url);
  }
}

class _Web extends PlatformWebViewController {
  _Web(super.params) : super.implementation();
  String url = 'https://www.v2ex.com/signin';
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setUserAgent(String? ua) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate d,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams p) async {
    url = p.uri.toString();
  }

  @override
  Future<String?> currentUrl() async => url;
  @override
  Future<void> runJavaScript(String script) async {}
  @override
  Future<Object> runJavaScriptReturningResult(String script) =>
      throw StateError(
        'Completion must not depend on DOM or JS string encoding',
      );
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  late PageEventCallback finished;
  late ProgressCallback progress;
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {
    progress = callback;
  }
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox(key: Key('fake-web'));
}

class _Bridge extends WebCookieBridge {
  String? header = 'A2=session';
  int reads = 0;
  int missingReads = 0;
  @override
  Future<void> clearCookies(String url) async {}
  @override
  Future<String?> cookieHeader(String url) async {
    reads++;
    return reads <= missingReads ? null : header;
  }
}

class _Auth extends AuthController {
  bool accept = true;
  int checks = 0;
  @override
  Future<AuthSession> build() async => const AuthSession.signedOut();
  @override
  Future<void> refreshAccount() async {}
  @override
  Future<void> signInWithCookies(Iterable<Cookie> cookies) async {
    checks++;
    state = AsyncData(
      accept
          ? const AuthSession(user: V2User(username: 'tester'))
          : const AuthSession.signedOut(),
    );
  }
}

class _Api extends FixtureV2exApi {
  @override
  Future<V2LoginForm?> loginForm() async => const V2LoginForm(
    usernameFieldName: 'u',
    passwordFieldName: 'p',
    captchaFieldName: 'c',
    once: 'once',
    next: '/',
    captchaPath: '/captcha',
  );
  @override
  Future<List<int>> captchaImage(String path, {String? once}) async =>
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );
}

void main() {
  late _WebPlatform platform;
  late _Bridge bridge;
  late _Auth auth;
  setUp(() {
    platform = _WebPlatform();
    WebViewPlatform.instance = platform;
    bridge = _Bridge();
    auth = _Auth();
    SharedPreferences.setMockInitialValues({});
  });
  Future<GoRouter> boot(WidgetTester tester, {bool direct = false}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/topic',
      routes: [
        GoRoute(
          path: '/topic',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  context.push(direct ? '/login/google' : '/login'),
              child: const Text('登录入口'),
            ),
          ),
        ),
        GoRoute(path: '/login', builder: (_, state) => const LoginPage()),
        GoRoute(
          path: '/login/google',
          builder: (_, state) => const GoogleLoginPage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        v2exApiProvider.overrideWithValue(_Api()),
        webCookieBridgeProvider.overrideWithValue(bridge),
        authControllerProvider.overrideWith(() => auth),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: Mv2ThemeData.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('登录入口'));
    if (!direct) {
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in with Google'));
    }
    await tester.pump(const Duration(milliseconds: 400));
    platform.finish('https://www.v2ex.com/signin');
    await tester.pump();
    return router;
  }

  testWidgets(
    'mobile page without signout DOM validates and returns to original topic once',
    (tester) async {
      final router = await boot(tester);
      platform.finish('https://www.v2ex.com/');
      platform.finish('https://www.v2ex.com/');
      await tester.pumpAndSettle();
      expect(find.byType(GoogleLoginPage), findsNothing);
      expect(find.byType(LoginPage), findsNothing);
      expect(router.canPop(), isFalse);
      expect(auth.checks, 1);
      expect(find.text('登录入口'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('delayed cookie retries before completing login', (tester) async {
    bridge.missingReads = 1;
    final router = await boot(tester);
    platform.finish('https://www.v2ex.com/');
    await tester.pump();
    expect(find.byType(GoogleLoginPage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.byType(GoogleLoginPage), findsNothing);
    expect(find.byType(LoginPage), findsNothing);
    expect(router.canPop(), isFalse);
    expect(bridge.reads, 2);
  });
  testWidgets('unvalidated cookies never dismiss login and retry can recover', (
    tester,
  ) async {
    auth.accept = false;
    final router = await boot(tester);
    platform.finish('https://www.v2ex.com/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.byType(GoogleLoginPage), findsOneWidget);
    expect(find.text('重新同步'), findsOneWidget);
    auth.accept = true;
    await tester.tap(find.text('重新同步'));
    await tester.pumpAndSettle();
    expect(find.byType(GoogleLoginPage), findsNothing);
    expect(find.byType(LoginPage), findsNothing);
    expect(router.canPop(), isFalse);
  });
  testWidgets('direct Google entry returns once without popping the caller', (
    tester,
  ) async {
    final router = await boot(tester, direct: true);
    platform.finish('https://www.v2ex.com/');
    await tester.pumpAndSettle();
    expect(find.text('登录入口'), findsOneWidget);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'cancelling during cookie retry does not update or dismiss the caller',
    (tester) async {
      bridge.missingReads = 99;
      final router = await boot(tester);
      platform.finish('https://www.v2ex.com/');
      await tester.pump();
      router.pop();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(auth.checks, 0);
      expect(bridge.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('external and OAuth intermediate pages never import cookies', (
    tester,
  ) async {
    await boot(tester);
    platform.finish('https://accounts.google.com/');
    await tester.pump();
    platform.finish('https://www.v2ex.com.attacker.invalid/');
    await tester.pump();
    platform.finish('http://www.v2ex.com/');
    await tester.pump();
    platform.finish('https://www.v2ex.com/auth/google?code=placeholder');
    await tester.pump();
    expect(bridge.reads, 0);
    expect(auth.checks, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
