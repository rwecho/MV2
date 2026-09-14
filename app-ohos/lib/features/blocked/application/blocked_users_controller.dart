import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/blocked_users_store.dart';

/// Storage handle for the 屏蔽用户 preference list.
final blockedUsersStoreProvider = Provider<BlockedUsersStore>(
  (ref) => const BlockedUsersStore(),
);

/// Lower-cased-comparison-free set of blocked usernames.
///
/// Hydration is async (SharedPreferences); the first frame renders the empty
/// set and rebuilds once storage answers, matching `SettingsController`.
class BlockedUsersController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    Future<void>(() => _hydrate());
    return <String>{};
  }

  Future<void> _hydrate() async {
    state = await ref.read(blockedUsersStoreProvider).load();
  }

  /// Blocks [username] (no-op when blank or already blocked).
  Future<void> block(String username) async {
    final name = username.trim();
    if (name.isEmpty || state.contains(name)) return;
    state = <String>{...state, name};
    await ref.read(blockedUsersStoreProvider).save(state);
  }

  Future<void> unblock(String username) async {
    if (!state.contains(username)) return;
    state = state.where((String name) => name != username).toSet();
    await ref.read(blockedUsersStoreProvider).save(state);
  }

  Future<void> clear() async {
    if (state.isEmpty) return;
    state = <String>{};
    await ref.read(blockedUsersStoreProvider).save(state);
  }
}

final blockedUsersProvider =
    NotifierProvider<BlockedUsersController, Set<String>>(
      BlockedUsersController.new,
    );

/// Whether [username] is currently blocked — the hook the feed / topic pages
/// use to hide a user's content.
final isBlockedProvider = Provider.family<bool, String>((ref, username) {
  return ref.watch(blockedUsersProvider).contains(username);
});
