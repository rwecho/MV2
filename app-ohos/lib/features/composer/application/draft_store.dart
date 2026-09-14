import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists composer drafts so an accidental back gesture or a crash never
/// loses text (`docs/06` — composer draft status).
///
/// Storage is deliberately tiny and key-based; the composer debounces writes so
/// a fast typist does not hammer the platform channel.
class DraftStore {
  DraftStore([this._preferences]);

  SharedPreferences? _preferences;

  /// Draft key for a reply to `topicId`: `mv2.draft.topic.<id>`.
  static String topicKey(int topicId) => 'mv2.draft.topic.$topicId';

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  /// The stored draft, or `null` when there is none.
  Future<String?> read(String key) async => (await _prefs()).getString(key);

  /// Stores [value]; an all-whitespace draft removes the key instead of
  /// persisting noise.
  Future<void> write(String key, String value) async {
    final prefs = await _prefs();
    if (value.trim().isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, value);
  }

  Future<void> clear(String key) async => (await _prefs()).remove(key);
}

final draftStoreProvider = Provider<DraftStore>((ref) => DraftStore());
