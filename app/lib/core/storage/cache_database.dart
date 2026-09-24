import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

part 'cache_database.g.dart';

/// Raw response cache: the *parsed* models are never stored, so a parser
/// improvement immediately applies to cached pages instead of being masked by
/// stale serialized JSON.
///
/// Privacy note (`docs/12` §6, defect B6): only anonymous, cacheable paths are
/// ever written here — see `HttpCache.isCacheable`. Authenticated pages
/// (`/my/*`, `/notifications`, `/mission/*`, `/settings/*`) must never enter
/// the shared cache or the app could show another account's page.
class HttpCacheEntries extends Table {
  TextColumn get url => text()();
  TextColumn get body => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {url};
}

/// 稍后阅读 — a local-only reading list.
///
/// The topic is stored as a flat snapshot (author + node are denormalised) so
/// the list can be rebuilt into a `V2Topic` without touching the network or the
/// HTTP cache. `topicId` is the natural key: saving the same topic twice
/// replaces the previous row instead of duplicating it.
class ReadLaterEntries extends Table {
  IntColumn get topicId => integer()();
  TextColumn get title => text()();
  TextColumn get authorName => text()();
  TextColumn get authorAvatar => text().nullable()();
  TextColumn get nodeName => text()();
  TextColumn get nodeKey => text()();
  TextColumn get timeLabel => text()();
  IntColumn get replyCount => integer()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {topicId};
}

/// 浏览历史 — local-only browsing records.
///
/// Unlike [ReadLaterEntries] this table has no reply count: history is written
/// from the topic-detail fetch where only the fields V2EX renders are known,
/// and the list row tolerates a `0` reply count.
class HistoryEntries extends Table {
  IntColumn get topicId => integer()();
  TextColumn get title => text()();
  TextColumn get authorName => text()();
  TextColumn get authorAvatar => text().nullable()();
  TextColumn get nodeName => text()();
  TextColumn get nodeKey => text()();
  TextColumn get timeLabel => text()();
  DateTimeColumn get viewedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {topicId};
}

@DriftDatabase(
  tables: <Type>[HttpCacheEntries, ReadLaterEntries, HistoryEntries],
)
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'mv2_cache',
              // Web needs the sqlite3 WASM module and the drift worker served
              // next to the app (web/sqlite3.wasm, web/drift_worker.js).
              // Native platforms ignore this parameter.
              web: kIsWeb
                  ? DriftWebOptions(
                      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                      driftWorker: Uri.parse('drift_worker.js'),
                    )
                  : null,
            ),
      );

  @override
  int get schemaVersion => 2;

  /// Maximum number of history rows kept on disk; older rows are pruned on
  /// every [historyRecord]. Keeps the local history store bounded without a
  /// background job.
  static const int historyLimit = 200;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      // v1 stored only the anonymous page cache; v2 adds the two local
      // personal tables. Both are create-only, so no data backfill.
      if (from < 2) {
        await m.createTable(readLaterEntries);
        await m.createTable(historyEntries);
      }
    },
  );

  Future<CachedResponse?> read(String url, {required Duration maxAge}) async {
    final row = await (select(
      httpCacheEntries,
    )..where((table) => table.url.equals(url))).getSingleOrNull();
    if (row == null) return null;
    if (DateTime.now().difference(row.fetchedAt) > maxAge) return null;
    return CachedResponse(body: row.body, fetchedAt: row.fetchedAt);
  }

  Future<void> write(String url, String body) async {
    await into(httpCacheEntries).insertOnConflictUpdate(
      HttpCacheEntriesCompanion.insert(
        url: url,
        body: body,
        fetchedAt: DateTime.now(),
      ),
    );
  }

  Future<void> clear() => delete(httpCacheEntries).go();

  /// Sum of stored body lengths, used by 设置 → 清除缓存.
  Future<int> approximateSizeBytes() async {
    final rows = await select(httpCacheEntries).get();
    return rows.fold<int>(0, (sum, row) => sum + row.body.length);
  }

  // --------------------------------------------------------- 稍后阅读

  /// All saved topics, newest first.
  Future<List<ReadLaterEntry>> readLaterAll() {
    return (select(readLaterEntries)
          ..orderBy(<OrderingTerm Function($ReadLaterEntriesTable)>[
            ($ReadLaterEntriesTable t) => OrderingTerm.desc(t.savedAt),
          ]))
        .get();
  }

  /// Inserts or replaces the saved snapshot for `entry.topicId`.
  Future<void> readLaterAdd(ReadLaterEntriesCompanion entry) {
    return into(readLaterEntries).insertOnConflictUpdate(entry);
  }

  Future<void> readLaterRemove(int topicId) {
    return (delete(
      readLaterEntries,
    )..where(($ReadLaterEntriesTable t) => t.topicId.equals(topicId))).go();
  }

  Future<bool> readLaterContains(int topicId) async {
    final row =
        await (select(readLaterEntries)
              ..where(($ReadLaterEntriesTable t) => t.topicId.equals(topicId)))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> readLaterClear() => delete(readLaterEntries).go();

  // --------------------------------------------------------- 浏览历史

  /// All history rows, newest first.
  Future<List<HistoryEntry>> historyAll() {
    return (select(historyEntries)
          ..orderBy(<OrderingTerm Function($HistoryEntriesTable)>[
            ($HistoryEntriesTable t) => OrderingTerm.desc(t.viewedAt),
          ]))
        .get();
  }

  /// Upserts `entry` with `viewedAt = now` and prunes everything past
  /// [historyLimit] (oldest first), so the newest [historyLimit] rows survive.
  Future<void> historyRecord(HistoryEntriesCompanion entry) async {
    await into(historyEntries).insertOnConflictUpdate(
      entry.copyWith(viewedAt: Value<DateTime>(DateTime.now())),
    );
    final stale =
        await (select(historyEntries)
              ..orderBy(<OrderingTerm Function($HistoryEntriesTable)>[
                ($HistoryEntriesTable t) => OrderingTerm.desc(t.viewedAt),
              ])
              ..limit(historyLimit, offset: historyLimit))
            .get();
    if (stale.isEmpty) return;
    final staleIds = stale.map((HistoryEntry row) => row.topicId).toList();
    await (delete(
      historyEntries,
    )..where(($HistoryEntriesTable t) => t.topicId.isIn(staleIds))).go();
  }

  Future<void> historyRemove(int topicId) {
    return (delete(
      historyEntries,
    )..where(($HistoryEntriesTable t) => t.topicId.equals(topicId))).go();
  }

  Future<void> historyClear() => delete(historyEntries).go();
}

class CachedResponse {
  const CachedResponse({required this.body, required this.fetchedAt});

  final String body;
  final DateTime fetchedAt;
}
