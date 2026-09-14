import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/storage/cache_database.dart';
import 'package:mv2/features/blocked/domain/blocked_users_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only personal stores: 稍后阅读, 浏览历史 and 屏蔽用户.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReadLaterEntriesCompanion readLater(
    int id, {
    DateTime? savedAt,
    String title = '主题标题',
  }) {
    return ReadLaterEntriesCompanion.insert(
      topicId: Value<int>(id),
      title: title,
      authorName: 'user$id',
      nodeName: '程序员',
      nodeKey: 'programmer',
      timeLabel: '3 小时前',
      replyCount: id,
      savedAt: savedAt ?? DateTime(2024, 1, 1),
    );
  }

  HistoryEntriesCompanion history(
    int id, {
    DateTime? viewedAt,
    String title = '主题标题',
  }) {
    return HistoryEntriesCompanion.insert(
      topicId: Value<int>(id),
      title: title,
      authorName: 'user$id',
      nodeName: '程序员',
      nodeKey: 'programmer',
      timeLabel: '3 小时前',
      viewedAt: viewedAt ?? DateTime(2024, 1, 1),
    );
  }

  group('稍后阅读', () {
    late CacheDatabase database;

    setUp(() => database = CacheDatabase(NativeDatabase.memory()));
    tearDown(() => database.close());

    test('add / contains / remove / clear round-trip', () async {
      expect(await database.readLaterContains(1), isFalse);

      await database.readLaterAdd(readLater(1));
      expect(await database.readLaterContains(1), isTrue);
      final rows = await database.readLaterAll();
      expect(rows, hasLength(1));
      expect(rows.single.topicId, 1);
      expect(rows.single.authorName, 'user1');
      expect(rows.single.nodeKey, 'programmer');
      expect(rows.single.replyCount, 1);

      await database.readLaterRemove(1);
      expect(await database.readLaterContains(1), isFalse);
      expect(await database.readLaterAll(), isEmpty);

      await database.readLaterAdd(readLater(2));
      await database.readLaterAdd(readLater(3));
      await database.readLaterClear();
      expect(await database.readLaterAll(), isEmpty);
    });

    test('returns the newest save first', () async {
      final base = DateTime(2024, 1, 1);
      await database.readLaterAdd(readLater(1, savedAt: base));
      await database.readLaterAdd(
        readLater(3, savedAt: base.add(const Duration(seconds: 2))),
      );
      await database.readLaterAdd(
        readLater(2, savedAt: base.add(const Duration(seconds: 1))),
      );

      final ids = (await database.readLaterAll())
          .map((row) => row.topicId)
          .toList();
      expect(ids, <int>[3, 2, 1]);
    });

    test('saving the same topic replaces the previous row', () async {
      await database.readLaterAdd(readLater(1, title: 'first'));
      await database.readLaterAdd(readLater(1, title: 'second'));

      final rows = await database.readLaterAll();
      expect(rows, hasLength(1));
      expect(rows.single.title, 'second');
    });
  });

  group('浏览历史', () {
    late CacheDatabase database;

    setUp(() => database = CacheDatabase(NativeDatabase.memory()));
    tearDown(() => database.close());

    test('record upserts without duplicating and refreshes viewedAt', () async {
      // Pre-seed a stale row for the same topic, as if it had been viewed long
      // ago; recording it again must replace it in place.
      await database
          .into(database.historyEntries)
          .insert(history(1, viewedAt: DateTime(2000), title: 'stale'));

      final before = DateTime.now().subtract(const Duration(seconds: 30));
      await database.historyRecord(history(1, title: 'updated'));

      final rows = await database.historyAll();
      expect(rows, hasLength(1));
      expect(rows.single.topicId, 1);
      expect(rows.single.title, 'updated');
      expect(rows.single.viewedAt.isAfter(before), isTrue);
      expect(rows.single.viewedAt.isAfter(DateTime(2000)), isTrue);
    });

    test('caps at ${CacheDatabase.historyLimit} rows keeping the newest', () async {
      final base = DateTime.now().subtract(const Duration(days: 2));
      for (var i = 0; i < CacheDatabase.historyLimit; i++) {
        await database
            .into(database.historyEntries)
            .insert(
              history(1000 + i, viewedAt: base.add(Duration(seconds: i))),
            );
      }
      expect(
        await database.historyAll(),
        hasLength(CacheDatabase.historyLimit),
      );

      // One more view pushes the total past the cap and prunes the oldest row.
      await database.historyRecord(history(9999));

      final rows = await database.historyAll();
      expect(rows, hasLength(CacheDatabase.historyLimit));
      expect(rows.first.topicId, 9999);
      expect(rows.map((row) => row.topicId), isNot(contains(1000)));
    });

    test('returns the newest view first', () async {
      final base = DateTime(2024, 1, 1);
      await database
          .into(database.historyEntries)
          .insert(history(1, viewedAt: base));
      await database
          .into(database.historyEntries)
          .insert(history(3, viewedAt: base.add(const Duration(seconds: 2))));
      await database
          .into(database.historyEntries)
          .insert(history(2, viewedAt: base.add(const Duration(seconds: 1))));

      final ids = (await database.historyAll()).map((row) => row.topicId);
      expect(ids, <int>[3, 2, 1]);
    });

    test('remove and clear empty the store', () async {
      await database.historyRecord(history(1));
      await database.historyRecord(history(2));

      await database.historyRemove(1);
      expect((await database.historyAll()).map((row) => row.topicId), <int>[2]);

      await database.historyClear();
      expect(await database.historyAll(), isEmpty);
    });
  });

  group('屏蔽用户 store', () {
    test('round-trips through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = BlockedUsersStore();

      expect(await store.load(), isEmpty);

      await store.save(<String>{'bob', 'alice'});
      expect(await store.load(), <String>{'alice', 'bob'});

      // Persisted sorted for a stable, diff-friendly preference value.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(BlockedUsersStore.storageKey), <String>[
        'alice',
        'bob',
      ]);

      await store.save(<String>{});
      expect(await store.load(), isEmpty);
    });
  });
}
