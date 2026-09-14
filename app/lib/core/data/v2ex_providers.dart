import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/mv2_http_client.dart';
import '../storage/cache_database.dart';
import '../storage/http_cache.dart';
import 'v2ex_api.dart';

/// Development-only HTTP proxy, e.g.
/// `flutter run --dart-define=MV2_PROXY=http://127.0.0.1:7897`.
///
/// Needed when the development network cannot reach `www.v2ex.com` directly.
/// The app itself always talks to the live site; a failed request surfaces as
/// the standard error state, never as canned data.
const String kDevProxyUrl = String.fromEnvironment('MV2_PROXY');

/// Single cookie-aware, paced HTTP client for the whole app.
final httpClientProvider = Provider<Mv2HttpClient>((ref) {
  return Mv2HttpClient.create(
    proxyUrl: kDevProxyUrl.isEmpty ? null : kDevProxyUrl,
  );
});

/// Drift database holding the anonymous page cache.
final cacheDatabaseProvider = Provider<CacheDatabase>((ref) {
  final database = CacheDatabase();
  ref.onDispose(database.close);
  return database;
});

final httpCacheProvider = Provider<HttpCache>(
  (ref) => HttpCache(ref.watch(cacheDatabaseProvider)),
);

/// Approximate cache size in bytes, shown in 设置 → 清除缓存.
final cacheSizeProvider = FutureProvider<int>(
  (ref) => ref.watch(httpCacheProvider).sizeBytes(),
);

/// True while the last anonymous read was served from the disk cache.
///
/// Surfaced as a quiet banner so "the app works but one page fails" cannot be
/// mistaken for a broken page when the real cause is no connectivity.
class CacheFallbackController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool fromCache) {
    if (state != fromCache) state = fromCache;
  }
}

final cacheFallbackProvider = NotifierProvider<CacheFallbackController, bool>(
  CacheFallbackController.new,
);

final v2exApiProvider = Provider<V2exApi>((ref) {
  return RemoteV2exApi(
    ref.watch(httpClientProvider),
    cache: ref.watch(httpCacheProvider),
    onCacheFallback: (fromCache) {
      // Called from the data layer, never during a build.
      Future<void>.microtask(
        () => ref.read(cacheFallbackProvider.notifier).set(fromCache),
      );
    },
  );
});
