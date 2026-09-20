import 'cache_database.dart';

export 'cache_database.dart' show CachedResponse;

/// Disk cache for anonymous V2EX pages, so the read path keeps working offline
/// and the UI can show the legacy `fromCache` indicator honestly.
class HttpCache {
  HttpCache(this._database);

  final CacheDatabase _database;

  /// Seven days, matching the legacy client's TTL.
  static const Duration maxAge = Duration(days: 7);

  /// Paths that never carry account state and are therefore safe to share on
  /// disk. Everything else (write endpoints, `/my/*`, `/notifications`,
  /// `/mission/*`, `/settings/*`, `/signin`, `/new`) is excluded on purpose.
  static bool isCacheable(String path) {
    if (path.startsWith('/api/')) return true;
    final pathOnly = path.split('?').first;
    if (pathOnly == '/' || pathOnly == '/recent') return true;
    if (pathOnly.startsWith('/t/')) {
      final rest = pathOnly.substring(3);
      // `/t/{id}` yes; `/t/{id}/append` (a form with a CSRF token) no.
      return RegExp(r'^\d+$').hasMatch(rest);
    }
    if (pathOnly.startsWith('/go/')) return true;
    if (pathOnly.startsWith('/tag/')) return true;
    return false;
  }

  Future<String?> read(String path) async {
    if (!isCacheable(path)) return null;
    final cached = await _database.read(path, maxAge: maxAge);
    return cached?.body;
  }

  /// Like [read], but the caller picks the freshness window and gets the
  /// entry's age. This is the stale-while-revalidate entry point: callers
  /// serve the body only when `fetchedAt` is inside their freshness window,
  /// then revalidate against the network.
  Future<CachedResponse?> readEntry(String path, {required Duration maxAge}) async {
    if (!isCacheable(path)) return null;
    return _database.read(path, maxAge: maxAge);
  }

  Future<void> write(String path, String body) async {
    if (!isCacheable(path) || body.isEmpty) return;
    await _database.write(path, body);
  }

  Future<void> clear() => _database.clear();

  Future<int> sizeBytes() => _database.approximateSizeBytes();
}
