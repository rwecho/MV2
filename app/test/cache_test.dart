import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/storage/cache_database.dart';
import 'package:mv2/core/storage/http_cache.dart';

void main() {
  late CacheDatabase database;
  late HttpCache cache;

  setUp(() {
    database = CacheDatabase(NativeDatabase.memory());
    cache = HttpCache(database);
  });

  tearDown(() => database.close());

  test('round-trips an anonymous page', () async {
    await cache.write('/t/1', '<html>cached topic</html>');

    expect(await cache.read('/t/1'), '<html>cached topic</html>');
    expect(await cache.sizeBytes(), greaterThan(0));
  });

  test('refuses to persist authenticated paths', () async {
    await cache.write('/my/topics', '<html>private</html>');
    await cache.write('/notifications', '<html>private</html>');
    await cache.write('/t/1/append', '<html>private once token</html>');

    expect(await cache.read('/my/topics'), isNull);
    expect(await cache.read('/notifications'), isNull);
    expect(await cache.read('/t/1/append'), isNull);
    expect(await cache.sizeBytes(), 0);
  });

  test('overwrites an existing entry instead of duplicating it', () async {
    await cache.write('/t/1', 'first');
    await cache.write('/t/1', 'second');

    expect(await cache.read('/t/1'), 'second');
    expect(
      await database.select(database.httpCacheEntries).get(),
      hasLength(1),
    );
  });

  test('clear empties the store', () async {
    await cache.write('/t/1', 'a');
    await cache.write('/go/python', 'b');

    await cache.clear();

    expect(await cache.read('/t/1'), isNull);
    expect(await cache.sizeBytes(), 0);
  });

  test('expires entries older than the TTL', () async {
    await database
        .into(database.httpCacheEntries)
        .insert(
          HttpCacheEntriesCompanion.insert(
            url: '/t/1',
            body: 'stale',
            fetchedAt: DateTime.now().subtract(const Duration(days: 30)),
          ),
        );

    expect(await cache.read('/t/1'), isNull);
  });
}
