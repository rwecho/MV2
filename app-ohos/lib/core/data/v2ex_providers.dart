import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../network/mv2_http_client.dart';
import '../storage/cache_database.dart';
import '../storage/http_cache.dart';
import '../storage/ohos_cache_database.dart';
import 'v2ex_api.dart';

/// Set `--dart-define=MV2_FIXTURES=false` to talk to the live site.
///
/// Fixtures are the default while the development environment cannot reach
/// `www.v2ex.com`; both paths share the same parsers, so switching is a
/// one-line change and the UI never knows the difference.
const bool kUseFixtureApi = bool.fromEnvironment(
  'MV2_FIXTURES',
  defaultValue: true,
);

/// Development-only HTTP proxy, e.g.
/// `flutter run --dart-define=MV2_PROXY=http://127.0.0.1:7897`.
///
/// Needed when the development network cannot reach `www.v2ex.com` directly.
const String kDevProxyUrl = String.fromEnvironment('MV2_PROXY');

/// Single cookie-aware, paced HTTP client for the whole app.
final httpClientProvider = Provider<Mv2HttpClient>((ref) {
  return Mv2HttpClient.create(
    proxyUrl: kDevProxyUrl.isEmpty ? null : kDevProxyUrl,
  );
});

/// Drift database holding the anonymous page cache.
///
/// **ohos variant.** Mainline opens `driftDatabase(name: 'mv2_cache')`
/// unconditionally. HarmonyOS has no system `sqlite3` and
/// `sqlite3_flutter_libs` has no ohos support, but the `sqlite3` package's own
/// Dart build hook *does* compile one: `flutter build hap` emits
/// `build/native_assets/ohos/libs/arm64-v8a/libsqlite3.so` and the fork's
/// `enable-native-assets` flag registers it with the engine.
///
/// That makes the native Drift store the primary path on ohos, but loading is
/// unverifiable without a device, so ohos probes whether sqlite3 can be opened
/// and falls back to the `SharedPreferences`-backed [OhosPrefsCacheDatabase] if
/// not. The fallback keeps 浏览历史 / 稍后阅读 / page cache working (with the
/// documented limits in `ohos_cache_database.dart`) instead of erroring out.
///
/// The probe is deliberately gated on [TargetPlatform.ohos] rather than run
/// everywhere: `flutter test` executes on the host, where the mainline path is
/// known to work, and touching the sqlite3 FFI layer during provider
/// construction there perturbed the suite's async error reporting.
final cacheDatabaseProvider = Provider<CacheDatabase>((ref) {
  final database = _openCacheDatabase();
  ref.onDispose(database.close);
  return database;
});

CacheDatabase _openCacheDatabase() {
  if (defaultTargetPlatform != TargetPlatform.ohos) return CacheDatabase();
  try {
    sqlite.sqlite3.openInMemory().close();
    return CacheDatabase();
  } catch (error) {
    // Never fall back silently: on device the reason is only diagnosable from
    // the log (`hdc hilog | grep 'MV2: sqlite3'`). The usual cause is the
    // ohos asset bundle omitting NativeAssetsManifest.json, which leaves the
    // bundled libsqlite3.so unresolvable through its `@Native` asset id.
    debugPrint('MV2: sqlite3 native asset unavailable, using prefs store: $error');
    return OhosPrefsCacheDatabase();
  }
}

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
  if (kUseFixtureApi) return FixtureV2exApi();
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
