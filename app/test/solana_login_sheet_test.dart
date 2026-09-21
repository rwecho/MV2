import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/solana/base58.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/auth/data/auth_store.dart';
import 'package:mv2/features/auth/domain/auth_session.dart';
import 'package:mv2/features/auth/data/solana_wallet_store.dart';
import 'package:mv2/features/auth/presentation/login_page.dart';
import 'package:mv2/shared/models/account_info.dart';
import 'package:mv2/shared/models/login_form.dart';
import 'package:mv2/shared/models/models.dart';
import 'support/fixture_api.dart';

/// A 1x1 transparent PNG so `Image.memory` can decode in the test.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

List<int> _hexToBytes(String hex) {
  final result = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    result.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return result;
}

/// RFC 8032 §7.1 TEST 1 seed, as base58 — a syntactically valid 32-byte key
/// the sheet's parser accepts.
final String _validSeedBase58 = Base58.encode(
  _hexToBytes(
    '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
  ),
);

class _SignedInApi extends FixtureV2exApi {
  _SignedInApi() : super(latency: Duration.zero);

  /// Only turns signed-in **after** the Solana flow under test succeeds —
  /// a signed-in `currentUser` from the start would make the login page pop
  /// itself instead of rendering (that is its real already-signed-in branch).
  bool solanaSignedIn = false;

  @override
  Future<V2AccountInfo?> currentUser() async {
    if (!solanaSignedIn) return null;
    return const V2AccountInfo(
      user: V2User(username: 'someone', avatarUrl: 'https://example/a.png'),
    );
  }

  @override
  Future<V2LoginForm?> loginForm() async => const V2LoginForm(
    usernameFieldName: 'user',
    passwordFieldName: 'pass',
    captchaFieldName: 'captcha',
    once: 'once-1',
    next: '/',
    captchaPath: 'https://www.v2ex.com/_captcha',
  );

  @override
  Future<List<int>> captchaImage(String captchaPath, {String? once}) async =>
      _onePixelPng;
}

/// The controller's session store must not touch the keychain in tests
/// (`FlutterSecureStorage` has no test implementation — its platform call
/// never completes inside FakeAsync), same reason `auth_controller_test.dart`
/// carries its own memory store.
class _MemoryAuthStore extends AuthStore {
  AuthSession? session;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

class _MemoryWalletStore extends SolanaWalletStore {
  String? secretKey;
  String? address;

  @override
  Future<({String secretKey, String address})?> read() async {
    final secret = secretKey;
    if (secret == null) return null;
    return (secretKey: secret, address: address ?? '');
  }

  @override
  Future<void> write({
    required String secretKey,
    required String address,
  }) async {
    this.secretKey = secretKey;
    this.address = address;
  }

  @override
  Future<void> clear() async {
    secretKey = null;
    address = null;
  }
}

final Key _homeShellKey = UniqueKey();

Widget _homeShell() => Scaffold(
  key: _homeShellKey,
  body: const Text('HOME-SHELL'),
);

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (_, _) => _homeShell()),
    GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
  ],
);

Future<(_SignedInApi, _MemoryWalletStore, GoRouter)> _pumpLogin(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _SignedInApi();
  final walletStore = _MemoryWalletStore();
  final router = _router();
  final container = ProviderContainer(
    overrides: [
      v2exApiProvider.overrideWithValue(api),
      solanaWalletStoreProvider.overrideWithValue(walletStore),
      authStoreProvider.overrideWithValue(_MemoryAuthStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: Mv2ThemeData.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  // Push (not initialLocation) so the success flow's `context.pop()` has a
  // page to pop, exactly like opening 登录 from the app shell.
  router.push('/login');
  await tester.pumpAndSettle();
  return (api, walletStore, router);
}

Future<void> _openSolanaSheet(WidgetTester tester) async {
  await tester.tap(find.text('Sign in with Solana'));
  await tester.pumpAndSettle();
}

Future<void> _enterKeyAndSubmit(WidgetTester tester, String key) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Solana 私钥（base58）').first,
    key,
  );
  await tester.tap(find.text('签名并登录'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('login page offers Google and Solana next to the password form', (
    tester,
  ) async {
    await _pumpLogin(tester);

    expect(find.text('其他登录方式'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Sign in with Solana'), findsOneWidget);
  });

  testWidgets('an unparsable key is rejected before any network call', (
    tester,
  ) async {
    final (api, _, _) = await _pumpLogin(tester);
    await _openSolanaSheet(tester);

    await _enterKeyAndSubmit(tester, 'not base58!');

    expect(find.textContaining('无法识别的私钥格式'), findsOneWidget);
    expect(api.solanaMessages, isEmpty);
    // The sheet stays open for a retry.
    expect(find.text('签名并登录'), findsOneWidget);
  });

  testWidgets('a valid but unbound wallet lands on the binding guidance', (
    tester,
  ) async {
    final (api, _, _) = await _pumpLogin(tester);
    await _openSolanaSheet(tester);

    // The default fixture answer is "not linked".
    await _enterKeyAndSubmit(tester, _validSeedBase58);

    expect(find.textContaining('尚未绑定'), findsOneWidget);
    expect(find.text('打开 v2ex.com/solana 绑定'), findsOneWidget);
    // The web protocol's login message format is what the server verifies.
    expect(api.solanaMessages.single, matches('Sign in to V2EX: \\d+'));
  });

  testWidgets('a linked wallet signs in and closes both surfaces', (
    tester,
  ) async {
    final (api, _, _) = await _pumpLogin(tester);
    api.solanaResult = const V2SolanaLoginResult(success: true);
    api.solanaSignedIn = true;
    await _openSolanaSheet(tester);

    await _enterKeyAndSubmit(tester, _validSeedBase58);

    // Sheet + login page are both gone.
    expect(find.text('Sign in with Solana'), findsNothing);
    expect(find.byKey(_homeShellKey), findsOneWidget);
  });

  testWidgets('记住钱包 persists the key; the next visit signs in directly', (
    tester,
  ) async {
    final (api, walletStore, router) = await _pumpLogin(tester);
    api.solanaResult = const V2SolanaLoginResult(success: true);
    api.solanaSignedIn = true;
    await _openSolanaSheet(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Solana 私钥（base58）').first,
      _validSeedBase58,
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('签名并登录'));
    await tester.pumpAndSettle();

    expect(walletStore.secretKey, _validSeedBase58);
    expect(find.byKey(_homeShellKey), findsOneWidget);

    // Re-opening shows the saved-wallet view that signs in without retyping.
    router.push('/login');
    await tester.pumpAndSettle();
    await _openSolanaSheet(tester);
    expect(find.text('已保存的钱包'), findsOneWidget);
    expect(find.text('忘记此钱包'), findsOneWidget);

    await tester.tap(find.text('签名并登录'));
    await tester.pumpAndSettle();
    expect(find.byKey(_homeShellKey), findsOneWidget);
    expect(api.solanaMessages, hasLength(2));
  });
}
