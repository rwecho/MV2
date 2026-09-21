import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/deeplink/deep_link.dart';
import '../core/telemetry/mv2_analytics.dart';
import '../features/auth/presentation/google_login_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/blocked/presentation/blocked_users_page.dart';
import '../features/feed/presentation/home_feed_page.dart';
import '../features/library/presentation/history_page.dart';
import '../features/library/presentation/read_later_page.dart';
import '../features/my/presentation/my_nodes_page.dart';
import '../features/my/presentation/my_topic_list_page.dart';
import '../features/member/presentation/member_page.dart';
import '../features/nodes/presentation/all_nodes_page.dart';
import '../features/nodes/presentation/node_topic_page.dart';
import '../features/nodes/presentation/nodes_page.dart';
import '../features/notifications/presentation/notifications_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/reader/presentation/reader_page.dart';
import '../features/search/presentation/search_page.dart';
import '../features/pro/presentation/honor_wall_page.dart';
import '../features/pro/presentation/paywall_page.dart';
import '../features/settings/presentation/about_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shell/presentation/app_shell.dart';
import '../features/topic/presentation/topic_detail_page.dart';
import '../ui/utils/mv2_sheet_page.dart';

/// pageBuilder for the secondary destinations: a floating card on wide
/// viewports, the plain full-screen push on phones (see [mv2SheetPage]).
Page<dynamic> _sheet(BuildContext context, GoRouterState state, Widget child) =>
    mv2SheetPage<dynamic>(
      context: context,
      key: state.pageKey,
      // `mv2IsSheetLocation` matches on this name (openTopic pops the card
      // once a topic opens in the shell's detail pane).
      name: state.matchedLocation,
      child: child,
    );

/// Route table (`docs/03` §2 — declaration lives in `app/`).
///
/// Four shell branches keep the floating tab bar stable; topic detail,
/// composer, publish and settings are full-screen destinations that hide it
/// (`docs/06-page-specifications.md`).

/// The root navigator's key — lets code without a context under the navigator
/// (Home Screen quick actions, deep links arriving at the listener) reach it.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Locations served by the shell's four branches (`/feed` incl. its `search`
/// child, `/nodes`, `/notifications`, `/profile`). Navigating to one must
/// `go` — that is a branch switch — because `push` would stack a duplicate
/// full-screen page above the shell. Everything else in the table (topic
/// detail, the sheet cards) has to `push`: `go` would *become* the whole
/// stack, leaving the page nothing beneath to pop back to.
bool mv2IsShellBranchLocation(String location) =>
    location == '/nodes' ||
    location == '/notifications' ||
    location == '/profile' ||
    location == '/feed' ||
    location.startsWith('/feed/');

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    // A cold start from a link (`mv2://topic/123`, or a pasted V2EX URL the
    // platform handed us) opens straight into that page; everything else lands
    // on the home feed. Warm links are handled by `Mv2DeepLinkListener`.
    initialLocation: () {
      final route = Mv2DeepLink.routeFor(
        WidgetsBinding.instance.platformDispatcher.defaultRouteName,
      );
      // A sheet card must always sit above the shell (`mv2://member/x`): as
      // the base route it would dim an empty void with nothing to pop back
      // to. The deep-link listener pushes the card onto the feed instead.
      if (route != null && mv2IsSheetLocation(route)) return '/feed';
      return route ?? '/feed';
    }(),
    // The platform may also hand the raw link over *after* the router exists
    // (a warm link, or a cold start where iOS delivers `openURL` late), which
    // would otherwise hit go_router as `mv2://topic/123` — "no routes for
    // location". Normalise any recognisable link into its app route.
    redirect: (BuildContext context, GoRouterState state) {
      final uri = state.uri;
      final route = Mv2DeepLink.routeFor(uri.toString());
      if (route != null) {
        return route == uri.toString() ? null : route;
      }
      // A link the app cannot map (mv2://garbage, a foreign https URL that
      // reached the router) must not fall through to go_router's "no routes"
      // error page — land on the home feed instead. Bare app paths carry no
      // scheme and are left to normal matching. The same goes for `/` itself:
      // the shell lives at /feed, and `/` has never been a route.
      final scheme = uri.scheme.toLowerCase();
      if (scheme == 'mv2' || scheme == 'https' || scheme == 'http') {
        return '/feed';
      }
      if (uri.path == '/') return '/feed';
      return null;
    },
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/feed',
                builder: (context, state) => const HomeFeedPage(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'search',
                    // Same go_router 18 default-page issue as `/topic`:
                    // explicit MaterialPage keeps the iOS back-swipe.
                    pageBuilder: (context, state) => MaterialPage<dynamic>(
                      key: state.pageKey,
                      name: state.matchedLocation,
                      child: const SearchPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/nodes',
                builder: (context, state) => const NodesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/notifications',
                builder: (context, state) => const NotificationsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/topic/:id',
        // Explicit MaterialPage instead of `builder:` — go_router's default
        // page fell through to NoTransitionPage here, which dropped the
        // iOS interactive back-swipe (no Cupertino transition = no edge
        // gesture strip). The sheet pages already carry their own
        // MaterialPage for the same reason (see `mv2SheetPage`).
        pageBuilder: (context, state) => MaterialPage<dynamic>(
          key: state.pageKey,
          name: state.matchedLocation,
          child: TopicDetailPage(
            topicId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            // `/topic/123?floor=4` (from a `#reply4` link) opens at that reply.
            initialFloor: int.tryParse(
              state.uri.queryParameters['floor'] ?? '',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/reader',
        pageBuilder: (context, state) => _sheet(
          context,
          state,
          ReaderPage(
            url: state.uri.queryParameters['url'] ?? '',
            // `?mode=original` opens straight into 原文; absent → the persisted
            // 外链打开方式 setting decides.
            mode: state.uri.queryParameters['mode'],
          ),
        ),
      ),
      GoRoute(
        path: '/member/:username',
        pageBuilder: (context, state) => _sheet(
          context,
          state,
          MemberPage(username: state.pathParameters['username'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/nodes/all',
        pageBuilder: (context, state) =>
            _sheet(context, state, const AllNodesPage()),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (context, state) =>
            _sheet(context, state, const AboutPage()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            _sheet(context, state, const LoginPage()),
      ),
      GoRoute(
        path: '/login/google',
        pageBuilder: (context, state) =>
            _sheet(context, state, const GoogleLoginPage()),
      ),
      GoRoute(
        path: '/node/:key',
        pageBuilder: (context, state) => _sheet(
          context,
          state,
          NodeTopicPage(
            nodeName: state.pathParameters['key'] ?? '',
            // The slug is not the display name; callers pass it when known.
            displayName: state.uri.queryParameters['name'],
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            _sheet(context, state, const SettingsPage()),
      ),
      GoRoute(
        path: '/pro',
        pageBuilder: (context, state) => _sheet(
          context,
          state,
          PaywallPage(
            // `?source=` 归因付费墙入口，缺省视为设置页。
            source: state.uri.queryParameters['source'] ?? 'settings',
          ),
        ),
      ),
      GoRoute(
        path: '/honors',
        pageBuilder: (context, state) => _sheet(
          context,
          state,
          HonorWallPage(
            source: state.uri.queryParameters['source'] ?? 'settings',
          ),
        ),
      ),
      GoRoute(
        path: '/read-later',
        pageBuilder: (context, state) =>
            _sheet(context, state, const ReadLaterPage()),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (context, state) =>
            _sheet(context, state, const HistoryPage()),
      ),
      GoRoute(
        path: '/blocked-users',
        pageBuilder: (context, state) =>
            _sheet(context, state, const BlockedUsersPage()),
      ),
      GoRoute(
        path: '/my/topics',
        pageBuilder: (context, state) => _sheet(
          context,
          state,
          const MyTopicListPage(kind: MyListKind.topics),
        ),
      ),
      GoRoute(
        path: '/my/replies',
        pageBuilder: (context, state) => _sheet(
          context,
          state,
          const MyTopicListPage(kind: MyListKind.replies),
        ),
      ),
      GoRoute(
        path: '/my/favorites',
        pageBuilder: (context, state) => _sheet(
          context,
          state,
          const MyTopicListPage(kind: MyListKind.favorites),
        ),
      ),
      GoRoute(
        path: '/my/nodes',
        pageBuilder: (context, state) =>
            _sheet(context, state, const MyNodesPage()),
      ),
    ],
  );

  // screen_view:监听 delegate 的路由变化,一个监听器同时覆盖根导航与 4 个
  // branch(FirebaseAnalyticsObserver 挂不上去 — 根导航 observers 在 go_router
  // 构造时被拷贝,而 Firebase 启动必然晚于 router 构建)。screenName 用路由
  // 模板(`/topic/:id`),看板按模式聚合而不按具体 id 打散;同名去重,一次
  // 导航引发的多次通知只记一条。
  var lastScreen = '';
  void onRouteChanged() {
    final config = router.routerDelegate.currentConfiguration;
    if (config.matches.isEmpty) return;
    final screen = config.fullPath.isNotEmpty
        ? config.fullPath
        : config.uri.path;
    if (screen.isEmpty || screen == lastScreen) return;
    lastScreen = screen;
    Mv2Analytics.logScreenView(screenName: screen);
  }

  router.routerDelegate.addListener(onRouteChanged);
  ref.onDispose(() => router.routerDelegate.removeListener(onRouteChanged));
  return router;
});
