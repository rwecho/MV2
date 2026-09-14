import 'package:flutter/foundation.dart';
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
    // `microtask`, not `Future(...)`: a zero-duration `Timer` would still be
    // pending when a widget test that pumps once tears the tree down.
    Future<void>.microtask(_hydrate);
    return <String>{};
  }

  Future<void> _hydrate() async {
    // Hydration is fire-and-forget, so an exception here would be an *unhandled*
    // async error. `SharedPreferences.getInstance()` throws where the plugin is
    // not registered (notably `flutter test`); an empty block list is a far
    // better failure mode than a crash.
    final Set<String> loaded;
    try {
      loaded = await ref.read(blockedUsersStoreProvider).load();
    } catch (error) {
      debugPrint('MV2: blocked-users storage unavailable: $error');
      return;
    }
    if (!ref.mounted) return;
    state = loaded;
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
