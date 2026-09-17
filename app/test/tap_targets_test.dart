import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mv2/app/app.dart';
import 'package:mv2/app/router.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/auth/domain/auth_session.dart';
import 'package:mv2/features/auth/presentation/mv2_account_avatar.dart';
import 'package:mv2/features/nodes/presentation/all_nodes_page.dart';
import 'package:mv2/features/reader/application/open_external_url.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/node_visuals.dart';
import 'package:mv2/ui/components/node_card.dart';
import 'package:mv2/ui/components/notification_item.dart';
import 'package:mv2/ui/components/xna_item.dart';
import 'package:mv2/ui/primitives/mv2_avatar.dart';
import 'package:mv2/ui/primitives/mv2_buttons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_container.dart';

/// Regression tests for sub-element tap targets: a tappable card must not
/// swallow taps meant for the person/link inside it, and affordances that
/// promise navigation must actually navigate.
class _FakeAuth extends AuthController {
  _FakeAuth(this.session);

  final AuthSession session;

  @override
  Future<AuthSession> build() async => session;
}

/// Pumps [child] on `/` inside a real [GoRouter] whose stub destinations
/// render their location, so navigation can be asserted without needing the
/// destination page's data.
Future<void> pumpHarness(WidgetTester tester, {required Widget child}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
      GoRoute(
        path: '/member/:name',
        builder: (_, state) =>
            Scaffold(body: Text('member:${state.pathParameters['name']}')),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Text('login')),
      ),
      GoRoute(
        path: '/reader',
        builder: (_, state) =>
            Scaffold(body: Text('reader:${state.uri.queryParameters['url']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: router, theme: Mv2ThemeData.light()),
  );
  await tester.pump();
}

/// Boots the real app against the fixture API (phone size).
Future<ProviderContainer> bootApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [v2exApiProvider.overrideWithValue(fixtureApi())],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const Mv2App()),
  );
  // Fixture providers resolve after ~250ms and skeletons never settle.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

void main() {
  testWidgets(
    'notification avatar opens the member page, card opens the topic',
    (tester) async {
      var cardTaps = 0;
      const notification = V2Notification(
        id: 'n1',
        kind: NotificationKind.reply,
        actor: V2User(username: 'arlmy'),
        timeLabel: '1 小时前',
        quote: '赞',
        sourceTitle: '一些标题',
        topicId: 42,
      );
      await pumpHarness(
        tester,
        child: NotificationItem(
          notification: notification,
          onTap: () => cardTaps++,
        ),
      );

      await tester.tap(find.byType(Mv2Avatar));
      await tester.pumpAndSettle();
      expect(find.text('member:arlmy'), findsOneWidget);
      expect(
        cardTaps,
        0,
        reason: 'the avatar must not fall through to the card',
      );
    },
  );

  testWidgets('notification card body still opens the topic', (tester) async {
    var cardTaps = 0;
    const notification = V2Notification(
      id: 'n1',
      kind: NotificationKind.reply,
      actor: V2User(username: 'arlmy'),
      timeLabel: '1 小时前',
      quote: '赞',
      sourceTitle: '一些标题',
      topicId: 42,
    );
    await pumpHarness(
      tester,
      child: NotificationItem(
        notification: notification,
        onTap: () => cardTaps++,
      ),
    );

    await tester.tap(find.text('一些标题'));
    await tester.pumpAndSettle();
    expect(cardTaps, 1);
    expect(find.text('member:arlmy'), findsNothing);
  });

  testWidgets('XNA author opens the member page, article card still fires', (
    tester,
  ) async {
    var cardTaps = 0;
    const entry = V2XnaEntry(
      title: '一篇外部文章',
      url: 'https://blog.example.com/post',
      sourceName: '素生',
      author: V2User(username: 'arlmy'),
      timeLabel: '2 小时前',
    );
    await pumpHarness(
      tester,
      child: XnaItem(entry: entry, onTap: () => cardTaps++),
    );

    // The title area keeps the external-article action (tap it first: after
    // the navigation above this page is offstage).
    await tester.tap(find.text('一篇外部文章'));
    await tester.pump();
    expect(cardTaps, 1);

    // The member is its own tap target.
    await tester.tap(find.text('arlmy'));
    await tester.pumpAndSettle();
    expect(find.text('member:arlmy'), findsOneWidget);
    expect(cardTaps, 1, reason: 'the author must not trigger the article');
  });

  testWidgets('openExternalUrl follows the 外链打开方式 setting (reader default)', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      child: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () =>
              unawaited(openExternalUrl(context, 'https://example.com/post')),
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('reader:https://example.com/post'), findsOneWidget);
  });

  testWidgets('header avatar signed out opens the login sheet', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Mv2AccountAvatar()),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('login')),
        ),
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
        child: MaterialApp.router(
          routerConfig: router,
          theme: Mv2ThemeData.light(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(Mv2AccountAvatar));
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('header avatar signed in switches to the 我的 branch', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/feed',
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) => navigationShell,
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/feed',
                  builder: (_, _) => const Scaffold(
                    body: Column(
                      children: <Widget>[Mv2AccountAvatar(), Text('feed-page')],
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/nodes',
                  builder: (_, _) => const Scaffold(body: Text('nodes-page')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/notifications',
                  builder: (_, _) =>
                      const Scaffold(body: Text('notifications-page')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/profile',
                  builder: (_, _) => const Scaffold(body: Text('profile-page')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuth(const AuthSession(user: V2User(username: 'livid'))),
        ),
      ],
    );
    addTearDown(container.dispose);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: Mv2ThemeData.light(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('profile-page'), findsNothing);
    await tester.tap(find.byType(Mv2AccountAvatar));
    await tester.pumpAndSettle();
    expect(find.text('profile-page'), findsOneWidget);
  });

  testWidgets('NodeCard only draws the chevron when it is tappable', (
    tester,
  ) async {
    final node = NodeVisuals.node(key: 'programmer', name: '程序员');
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              NodeCard(node: node),
              NodeCard(node: node, onTap: () {}),
            ],
          ),
        ),
      ),
    );

    // Two cards, one chevron — the inert card must not promise navigation.
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('disabled icon button looks disabled and does nothing', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: Row(
            children: <Widget>[
              const Mv2IconButton(icon: Icons.ac_unit_rounded),
              Mv2IconButton(
                icon: Icons.beach_access_rounded,
                onPressed: () => taps++,
              ),
            ],
          ),
        ),
      ),
    );

    final disabled = tester.widget<Icon>(find.byIcon(Icons.ac_unit_rounded));
    final enabled = tester.widget<Icon>(
      find.byIcon(Icons.beach_access_rounded),
    );
    expect(disabled.color, isNot(enabled.color));

    await tester.tap(find.byIcon(Icons.ac_unit_rounded));
    expect(taps, 0);
  });

  testWidgets('nodes filter button opens the all-nodes filter page', (
    tester,
  ) async {
    final container = await bootApp(tester);

    container.read(routerProvider).go('/nodes');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AllNodesPage), findsNothing);
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AllNodesPage), findsOneWidget);
  });

  testWidgets('notifications header has no phantom search button', (
    tester,
  ) async {
    final container = await bootApp(tester);

    container.read(routerProvider).go('/notifications');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.search_rounded), findsNothing);
  });
}
