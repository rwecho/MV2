import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cache_database.dart';

/// HarmonyOS (ohos) replacement for the Drift-backed [CacheDatabase].
///
/// **Why this exists.** Mainline stores the anonymous page cache, 稍后阅读 and
/// 浏览历史 in a SQLite file opened by `drift_flutter`. HarmonyOS has no
/// `sqlite3` in the OpenHarmony sysroot (checked under
/// `<DevEco>/sdk/default/openharmony/native/sysroot/usr/lib/*`), `sqlite3`'s
/// Dart FFI loader does not know `ohos`, and there is no
/// `sqlite3_flutter_libs` port for ohos. Opening the Drift database on a device
/// therefore throws, and every read path that touches it would surface an error.
///
/// **What it does instead.** It subclasses [CacheDatabase] — so
/// `cacheDatabaseProvider`, `HttpCache`, `LibraryController` and the generated
/// row/companion types are all untouched — and overrides every method the app
/// calls with a `SharedPreferences` implementation. `shared_preferences` has a
/// real ohos implementation (`shared_preferences_ohos`), so this is real
/// on-device persistence rather than a memory-only stub.
///
/// The inert `NativeDatabase.memory()` executor passed to `super` is never
/// opened: it is lazy by construction and the [close] path in
/// `DelegatedDatabase` is a no-op for a database that was never opened. Every
/// method that would touch it is overridden below.
///
/// **Limits (documented in app-ohos/README.md):**
///   * values are stored as JSON in `SharedPreferences`, so the page cache is
///     capped at [httpCacheLimit] entries and writes re-serialise the whole
///     blob instead of one row;
///   * the 200-row history cap is enforced the same way;
///   * there is no transaction, so a crash mid-write can drop a cache entry
///     (never user-visible data, which is rewritten on the next view).
class OhosPrefsCacheDatabase extends CacheDatabase {
  OhosPrefsCacheDatabase() : super(NativeDatabase.memory());

  static const String _kHttpCache = 'mv2.ohos.store.httpCache';
  static const String _kReadLater = 'mv2.ohos.store.readLater';
  static const String _kHistory = 'mv2.ohos.store.history';

  /// Page-cache entries kept on device, newest first.
  static const int httpCacheLimit = 120;

  /// In-process fallback used when `SharedPreferences` is unavailable, so a
  /// broken preferences store degrades to "cache does not survive a restart"
  /// instead of "the feed cannot render".
  static final Map<String, String> _memoryFallback = <String, String>{};

  // ------------------------------------------------------------- plumbing

  Future<String?> _readString(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } catch (_) {
      return _memoryFallback[key];
    }
  }

  Future<void> _writeString(String key, String value) async {
    _memoryFallback[key] = value;
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } catch (_) {
      // In-memory copy already holds it for this run.
    }
  }

  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      // A truncated/corrupt blob must not brick history or read-later.
      return <Map<String, dynamic>>[];
    }
  }

  // ------------------------------------------------------- anonymous cache

  @override
  Future<CachedResponse?> read(String url, {required Duration maxAge}) async {
    final rows = _decodeList(await _readString(_kHttpCache));
    for (final row in rows) {
      if (row['url'] != url) continue;
      final fetchedAt = _dateTimeFrom(row['fetchedAt']);
      if (fetchedAt == null) return null;
      if (DateTime.now().difference(fetchedAt) > maxAge) return null;
      final body = row['body'];
      if (body is! String) return null;
      return CachedResponse(body: body, fetchedAt: fetchedAt);
    }
    return null;
  }

  @override
  Future<void> write(String url, String body) async {
    final rows = _decodeList(await _readString(_kHttpCache))
      ..removeWhere((row) => row['url'] == url);
    rows.insert(0, <String, dynamic>{
      'url': url,
      'body': body,
      'fetchedAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (rows.length > httpCacheLimit) {
      rows.removeRange(httpCacheLimit, rows.length);
    }
    await _writeString(_kHttpCache, jsonEncode(rows));
  }

  @override
  Future<void> clear() => _writeString(_kHttpCache, '[]');

  /// Sum of stored body lengths, matching the SQLite implementation's intent
  /// (设置 → 清除缓存 shows an approximate size).
  @override
  Future<int> approximateSizeBytes() async {
    var total = 0;
    for (final row in _decodeList(await _readString(_kHttpCache))) {
      final body = row['body'];
      if (body is String) total += body.length;
    }
    return total;
  }

  // -------------------------------------------------------------- 稍后阅读

  @override
  Future<List<ReadLaterEntry>> readLaterAll() async {
    final entries = <ReadLaterEntry>[];
    for (final row in _decodeList(await _readString(_kReadLater))) {
      try {
        entries.add(ReadLaterEntry.fromJson(row));
      } catch (_) {
        // Skip a single malformed record rather than losing the list.
      }
    }
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  @override
  Future<void> readLaterAdd(ReadLaterEntriesCompanion entry) async {
    final row = ReadLaterEntry(
      topicId: entry.topicId.value,
      title: entry.title.value,
      authorName: entry.authorName.value,
      authorAvatar: entry.authorAvatar.present
          ? entry.authorAvatar.value
          : null,
      nodeName: entry.nodeName.value,
      nodeKey: entry.nodeKey.value,
      timeLabel: entry.timeLabel.value,
      replyCount: entry.replyCount.value,
      savedAt: entry.savedAt.present ? entry.savedAt.value : DateTime.now(),
    );
    final rows = _decodeList(await _readString(_kReadLater))
      ..removeWhere((existing) => existing['topicId'] == row.topicId)
      ..insert(0, row.toJson());
    await _writeString(_kReadLater, jsonEncode(rows));
  }

  @override
  Future<void> readLaterRemove(int topicId) async {
    final rows = _decodeList(await _readString(_kReadLater))
      ..removeWhere((row) => row['topicId'] == topicId);
    await _writeString(_kReadLater, jsonEncode(rows));
  }

  @override
  Future<bool> readLaterContains(int topicId) async {
    final rows = _decodeList(await _readString(_kReadLater));
    return rows.any((row) => row['topicId'] == topicId);
  }

  @override
  Future<void> readLaterClear() => _writeString(_kReadLater, '[]');

  // -------------------------------------------------------------- 浏览历史

  @override
  Future<List<HistoryEntry>> historyAll() async {
    final entries = <HistoryEntry>[];
    for (final row in _decodeList(await _readString(_kHistory))) {
      try {
        entries.add(HistoryEntry.fromJson(row));
      } catch (_) {
        // See readLaterAll.
      }
    }
    entries.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return entries;
  }

  @override
  Future<void> historyRecord(HistoryEntriesCompanion entry) async {
    final stamped = entry.copyWith(viewedAt: Value<DateTime>(DateTime.now()));
    final row = HistoryEntry(
      topicId: stamped.topicId.value,
      title: stamped.title.value,
      authorName: stamped.authorName.value,
      authorAvatar: stamped.authorAvatar.present
          ? stamped.authorAvatar.value
          : null,
      nodeName: stamped.nodeName.value,
      nodeKey: stamped.nodeKey.value,
      timeLabel: stamped.timeLabel.value,
      viewedAt: stamped.viewedAt.value,
    );
    final rows = _decodeList(await _readString(_kHistory))
      ..removeWhere((existing) => existing['topicId'] == row.topicId)
      ..insert(0, row.toJson());
    if (rows.length > CacheDatabase.historyLimit) {
      rows.removeRange(CacheDatabase.historyLimit, rows.length);
    }
    await _writeString(_kHistory, jsonEncode(rows));
  }

  @override
  Future<void> historyRemove(int topicId) async {
    final rows = _decodeList(await _readString(_kHistory))
      ..removeWhere((row) => row['topicId'] == topicId);
    await _writeString(_kHistory, jsonEncode(rows));
  }

  @override
  Future<void> historyClear() => _writeString(_kHistory, '[]');

  // ----------------------------------------------------------------- utils

  /// drift's default `ValueSerializer` writes `DateTime` as epoch millis; the
  /// [ReadLaterEntry] / [HistoryEntry] `toJson`/`fromJson` pair round-trips
  /// through it. Be liberal when reading legacy/hand-edited values.
  static DateTime? _dateTimeFrom(Object? raw) {
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
