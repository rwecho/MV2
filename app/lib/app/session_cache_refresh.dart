import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/session_once.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/daily_mission_providers.dart';
import '../features/auth/domain/auth_session.dart';
import '../features/notifications/application/notifications_providers.dart';
import '../features/topic/application/topic_providers.dart';

/// Drops session-scoped caches whenever the signed-in state changes.
///
/// V2EX renders `once`, 收藏/感谢/忽略 state and notifications **per session**,
/// while these providers are long-lived by design (they are not `autoDispose`,
/// so a page is not refetched just because the route was popped). A page fetched
/// while signed out therefore keeps serving its anonymous copy after the user
/// signs in. That is exactly why the reply composer's 发送 button stayed
/// disabled: its cached topic detail carried no `once`, and nothing refetched it.
///
/// Watched once from the app root (`app.dart`), so the invalidation does not
/// depend on which route is on screen.
final sessionCacheRefreshProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AuthSession>>(authControllerProvider, (previous, next) {
    final session = next.value;
    // Loading (including a refresh that dropped its value) is not a transition.
    if (session == null) return;
    final wasSignedIn = previous?.value?.isSignedIn ?? false;
    if (wasSignedIn == session.isSignedIn) return;

    // The token belongs to the session that issued it.
    ref.read(sessionOnceProvider.notifier).reset();

    ref.invalidate(topicDetailProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(notificationsPageProvider);
    ref.invalidate(dailyMissionProvider);
  });
});
