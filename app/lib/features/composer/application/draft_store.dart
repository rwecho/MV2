import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists composer drafts so an accidental back gesture or a crash never
/// loses text (`docs/06` — composer draft status).
///
/// Storage is deliberately tiny and key-based; the composer debounces writes so
/// a fast typist does not hammer the platform channel.
///
/// Values are JSON-encoded behind [_encodedPrefix] before they reach
/// `SharedPreferences`. Android's legacy plugin refuses to store strings that
/// start with the platform's list/double/BigInteger markers, so writing the raw
/// draft turns legitimate user text (for example a base64 paste) into a
/// permanent "草稿保存失败". The marker keeps every stored value inside the
/// plain-string namespace; drafts written by older builds are still read
/// verbatim and are re-encoded on their next save.
class DraftStore {
  DraftStore([this._preferences]);

  SharedPreferences? _preferences;

  static const String _encodedPrefix = 'mv2.draft.v2:';

  /// Draft key for a reply to `topicId`: `mv2.draft.topic.<id>`.
  static String topicKey(int topicId) => 'mv2.draft.topic.$topicId';

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  /// The stored draft, or `null` when there is none.
  ///
  /// A value without [_encodedPrefix] predates the encoding (or was written by
  /// a test) and is returned as-is so existing drafts survive the upgrade.
  Future<String?> read(String key) async {
    final raw = (await _prefs()).getString(key);
    if (raw == null) return null;
    if (!raw.startsWith(_encodedPrefix)) return raw;
    final decoded = jsonDecode(raw.substring(_encodedPrefix.length));
    if (decoded is! String) {
      throw FormatException('draft is not a string', key);
    }
    return decoded;
  }

  /// Stores [value]; an all-whitespace draft removes the key instead of
  /// persisting noise.
  Future<void> write(String key, String value) async {
    final prefs = await _prefs();
    if (value.trim().isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, '$_encodedPrefix${jsonEncode(value)}');
  }

  Future<void> clear(String key) async => (await _prefs()).remove(key);
}

final draftStoreProvider = Provider<DraftStore>((ref) => DraftStore());
