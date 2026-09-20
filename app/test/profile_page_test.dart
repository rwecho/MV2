import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/auth/domain/auth_session.dart';
import 'package:mv2/features/profile/presentation/profile_page.dart';

/// 「我的」页入口行：赞助榜常驻（不依赖登录态），点击带
/// `source=profile` 进 /honors；设置页的入口已挪到此处。
class _FakeAuth extends AuthController {
  _FakeAuth(this.session);

  final AuthSession session;

  @override
  Future<AuthSession> build() async => session;
}

Future<GoRouter> _pump(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const ProfilePage(),
      ),
      GoRoute(
        path: '/honors',
        builder: (context, state) =>
            Text('honors:${state.uri.queryParameters['source']}'),
      ),
      GoRoute(
        path: '/my/topics',
        builder: (_, _) => const Text('my-topics'),
      ),
      GoRoute(
        path: '/my/replies',
        builder: (_, _) => const Text('my-replies'),
      ),
      GoRoute(
        path: '/my/favorites',
        builder: (_, _) => const Text('my-favorites'),
      ),
      GoRoute(
        path: '/read-later',
        builder: (_, _) => const Text('read-later'),
      ),
      GoRoute(
        path: '/history',
        builder: (_, _) => const Text('history'),
      ),
      GoRoute(
        path: '/blocked-users',
        builder: (_, _) => const Text('blocked-users'),
      ),
      GoRoute(
        path: '/my/nodes',
        builder: (_, _) => const Text('my-nodes'),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const Text('notifications'),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Text('settings'),
      ),
      GoRoute(path: '/login', builder: (_, _) => const Text('login')),
    ],
  );
  addTearDown(router.dispose);

  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        () => _FakeAuth(const AuthSession.signedOut()),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router, theme: Mv2ThemeData.light()),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('赞助榜 entry is always visible on 我的, signed out included', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('赞助榜'), findsOneWidget);
  });

  testWidgets('tapping 赞助榜 opens /honors with source=profile', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('赞助榜'));
    await tester.pumpAndSettle();

    expect(find.text('honors:profile'), findsOneWidget);
  });
}
