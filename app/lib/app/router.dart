import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/deeplink/deep_link.dart';
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
import '../features/settings/presentation/about_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shell/presentation/app_shell.dart';
import '../features/topic/presentation/topic_detail_page.dart';

/// Route table (`docs/03` §2 — declaration lives in `app/`).
///
/// Four shell branches keep the floating tab bar stable; topic detail,
/// composer, publish and settings are full-screen destinations that hide it
/// (`docs/06-page-specifications.md`).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    // A cold start from a link (`mv2://topic/123`, or a pasted V2EX URL the
    // platform handed us) opens straight into that page; everything else lands
    // on the home feed. Warm links are handled by `Mv2DeepLinkListener`.
    initialLocation:
        Mv2DeepLink.routeFor(
          WidgetsBinding.instance.platformDispatcher.defaultRouteName,
        ) ??
        '/feed',
    // The platform may also hand the raw link over *after* the router exists
    // (a warm link, or a cold start where iOS delivers `openURL` late), which
    // would otherwise hit go_router as `mv2://topic/123` — "no routes for
    // location". Normalise any recognisable link into its app route.
    redirect: (BuildContext context, GoRouterState state) {
      final route = Mv2DeepLink.routeFor(state.uri.toString());
      return route == state.uri.toString() ? null : route;
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
                    builder: (context, state) => const SearchPage(),
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
        builder: (context, state) => TopicDetailPage(
          topicId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          // `/topic/123?floor=4` (from a `#reply4` link) opens at that reply.
          initialFloor: int.tryParse(state.uri.queryParameters['floor'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/reader',
        builder: (context, state) => ReaderPage(
          url: state.uri.queryParameters['url'] ?? '',
          // `?mode=original` opens straight into 原文; absent → the persisted
          // 外链打开方式 setting decides.
          mode: state.uri.queryParameters['mode'],
        ),
      ),
      GoRoute(
        path: '/member/:username',
        builder: (context, state) =>
            MemberPage(username: state.pathParameters['username'] ?? ''),
      ),
      GoRoute(
        path: '/nodes/all',
        builder: (context, state) => const AllNodesPage(),
      ),
      GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/node/:key',
        builder: (context, state) => NodeTopicPage(
          nodeName: state.pathParameters['key'] ?? '',
          // The slug is not the display name; callers pass it when known.
          displayName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/read-later',
        builder: (context, state) => const ReadLaterPage(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryPage(),
      ),
      GoRoute(
        path: '/blocked-users',
        builder: (context, state) => const BlockedUsersPage(),
      ),
      GoRoute(
        path: '/my/topics',
        builder: (context, state) =>
            const MyTopicListPage(kind: MyListKind.topics),
      ),
      GoRoute(
        path: '/my/replies',
        builder: (context, state) =>
            const MyTopicListPage(kind: MyListKind.replies),
      ),
      GoRoute(
        path: '/my/favorites',
        builder: (context, state) =>
            const MyTopicListPage(kind: MyListKind.favorites),
      ),
      GoRoute(
        path: '/my/nodes',
        builder: (context, state) => const MyNodesPage(),
      ),
    ],
  );
});
