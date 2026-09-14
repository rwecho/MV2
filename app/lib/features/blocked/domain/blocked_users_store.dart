import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-backed store for 屏蔽用户.
///
/// Blocking is a preference (a flat username list), not tabular data, so it
/// lives in preferences rather than the Drift database. Values are sorted on
/// write so the stored list is stable and diff-friendly.
class BlockedUsersStore {
  const BlockedUsersStore();

  /// Preference key; the app owns this namespace.
  static const String storageKey = 'mv2.blockedUsers';

  Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(storageKey) ?? const <String>[]).toSet();
  }

  Future<void> save(Set<String> usernames) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = usernames.toList()..sort();
    await prefs.setStringList(storageKey, sorted);
  }
}
