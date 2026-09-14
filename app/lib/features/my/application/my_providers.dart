import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/provider_retry.dart';
import '../../../shared/models/models.dart';
import '../../auth/application/auth_controller.dart';
import '../data/my_api.dart';

/// Feature-local data source wired to the shared cookie-aware HTTP client.
///
/// The signed-in member name is read from the auth session because 我的主题 /
/// 我的回复 are member-scoped pages (`/member/{username}/…`).
final myApiProvider = Provider<MyApi>((ref) {
  return MyApi(
    ref.watch(httpClientProvider),
    username: ref.watch(currentUsernameProvider),
  );
});

/// 我的主题 — the member's own topics. Empty (no request) while signed out.
final myTopicsProvider = FutureProvider.autoDispose<MyTopicPage>((ref) {
  if (!ref.watch(isSignedInProvider)) return MyTopicPage.empty;
  return ref.watch(myApiProvider).myTopics();
}, retry: mv2Retry);

/// 我的回复 — topics the member replied to. Empty (no request) while signed out.
final myRepliesProvider = FutureProvider.autoDispose<MyTopicPage>((ref) {
  if (!ref.watch(isSignedInProvider)) return MyTopicPage.empty;
  return ref.watch(myApiProvider).myReplies();
}, retry: mv2Retry);

/// 收藏 — the member's favourite topics. Empty (no request) while signed out.
final favoriteTopicsProvider = FutureProvider.autoDispose<MyTopicPage>((ref) {
  if (!ref.watch(isSignedInProvider)) return MyTopicPage.empty;
  return ref.watch(myApiProvider).favoriteTopics();
}, retry: mv2Retry);

/// 我的节点 — the member's favourite nodes. Empty (no request) while signed out.
final favoriteNodesProvider = FutureProvider.autoDispose<List<V2Node>>((ref) {
  if (!ref.watch(isSignedInProvider)) return const <V2Node>[];
  return ref.watch(myApiProvider).favoriteNodes();
}, retry: mv2Retry);
