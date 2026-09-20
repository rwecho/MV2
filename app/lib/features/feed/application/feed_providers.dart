import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/cache_ttl.dart';
import '../../../core/data/home_tab.dart';
import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/provider_retry.dart';
import '../../../core/network/mv2_http_client.dart';
import '../../../core/telemetry/mv2_analytics.dart';
import '../../../shared/models/models.dart';
import '../../blocked/application/blocked_content.dart';
import '../../blocked/application/blocked_users_controller.dart';
import 'feed_idle_prefetch.dart';

/// Currently selected home tab (`技术 … VXNA`).
///
/// The choice is persisted: first run selects [HomeTab.initial] (`R2`) and
/// every later launch restores the last tab, matching the "动态选中 + 记住上
/// 次" behaviour. Hydration follows the `SettingsController` pattern — the UI
/// renders the default for the first frame and rebuilds once storage answers.
class HomeTabController extends Notifier<HomeTab> {
  /// `SharedPreferences` key holding the persisted [HomeTab.name].
  static const String storageKey = 'mv2.homeTab';

  SharedPreferences? _prefs;

  @override
  HomeTab build() {
    Future<void>(() async => _hydrate());
    return HomeTab.initial;
  }

  Future<void> _hydrate() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    // The first frame may be disposed (tests, hot restart) before storage
    // answers; writing state then would throw `UnmountedRefException`.
    if (!ref.mounted) return;
    state = HomeTab.fromName(prefs.getString(storageKey)) ?? HomeTab.initial;
  }

  Future<void> select(HomeTab tab) async {
    if (state == tab) return;
    state = tab;
    // 点标签与 PageView 横滑都汇到这里(单一咽喉点);_hydrate 直写 state
    // 不经 select,启动恢复不会误记为一次浏览。
    Mv2Analytics.logFeedTabView(tab: tab.slug);
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(storageKey, tab.name);
  }
}

final homeTabProvider = NotifierProvider<HomeTabController, HomeTab>(
  HomeTabController.new,
);

/// Topic list for one topic tab — stale-while-revalidate (磁盘换时间).
///
/// First render serves the disk cache when it is inside [CacheTtl.feedFresh]
/// and immediately revalidates against the network in the background; the
/// fresh list swaps in place a second later. No fresh cache → network with
/// the usual skeleton. Pull-to-refresh ([FeedController.refresh]) always
/// bypasses the cache. Entries are kept alive per tab so swiping back does
/// not refetch.
///
/// 屏蔽用户 is applied here so every consumer (home, and anything that reuses
/// this provider) sees the same filtered list.
class FeedController extends AsyncNotifier<List<V2Topic>> {
  FeedController(this.tab);

  final HomeTab tab;

  /// Dedupes revalidation across build() re-runs (e.g. a blocked-users change
  /// rebuilds without recreating the notifier).
  Future<void>? _revalidating;

  /// When the last background revalidation finished. A cache entry served
  /// within [CacheTtl.feedFresh] of that moment is the result of a fetch this
  /// controller itself just made — revalidating it again would only burn
  /// quota (blocked-users changes rebuild this provider, but the data cannot
  /// have gone stale in between).
  DateTime? _lastRevalidateAt;

  /// Set once neighbor tabs have been queued for idle prefetch.
  bool _prefetchQueued = false;

  @override
  Future<List<V2Topic>> build() async {
    // The aggregator tab is not a topic list; the page routes it to
    // [xnaFeedProvider]. Guard anyway so a stray feedProvider(vxna) stays
    // inert instead of parsing /xna HTML as a topic list.
    if (tab.isAggregator) return const <V2Topic>[];
    final api = ref.watch(v2exApiProvider);
    final blocked = ref.watch(blockedUsersProvider);
    final cached = await _safeCached();
    if (cached != null) {
      final age = DateTime.now().difference(cached.fetchedAt);
      Mv2Analytics.logFeedCacheHit(
        tab: tab.slug,
        ageSec: age.inSeconds,
      );
      unawaited(_revalidate());
      return BlockedContent.topics(blocked, cached.topics);
    }
    final topics = await api.feed(tab);
    _queueIdlePrefetch();
    return BlockedContent.topics(blocked, topics);
  }

  /// Pull-to-refresh: always the network, bypassing the freshness window, so
  /// the gesture can never "do nothing" on a freshly cached tab.
  Future<void> refresh() async {
    final stopwatch = Stopwatch()..start();
    try {
      final topics = await ref
          .read(v2exApiProvider)
          .feed(tab, priority: PacePriority.userRead);
      stopwatch.stop();
      if (ref.mounted) {
        state = AsyncData(
          BlockedContent.topics(ref.read(blockedUsersProvider), topics),
        );
      }
      _queueIdlePrefetch();
    } catch (error, stack) {
      stopwatch.stop();
      // Surface the failure like the pre-SWR provider did (recompute error →
      // error branch + retry), but still complete the gesture's future.
      if (ref.mounted) state = AsyncError(error, stack);
      rethrow;
    }
  }

  /// Background refresh after a cache hit. Failures are swallowed: the user
  /// is already looking at valid data and must not be kicked off it.
  Future<void> _revalidate() {
    final inFlight = _revalidating;
    if (inFlight != null) return inFlight;
    final last = _lastRevalidateAt;
    if (last != null &&
        DateTime.now().difference(last) <= CacheTtl.feedFresh) {
      return Future<void>.value();
    }
    return _revalidating = () async {
      final stopwatch = Stopwatch()..start();
      var ok = false;
      try {
        final topics = await ref
            .read(v2exApiProvider)
            .feed(tab, priority: PacePriority.backgroundRead);
        ok = true;
        if (ref.mounted) {
          state = AsyncData(
            BlockedContent.topics(ref.read(blockedUsersProvider), topics),
          );
        }
      } on Failure {
        // Cache stays on screen; the offline fallback chain remains intact.
      } finally {
        stopwatch.stop();
        Mv2Analytics.logFeedRevalidate(
          tab: tab.slug,
          ok: ok,
          durationMs: stopwatch.elapsedMilliseconds,
        );
        _lastRevalidateAt = DateTime.now();
        _revalidating = null;
        _queueIdlePrefetch();
      }
    }();
  }

  /// Cache read that can never throw: a broken cache must not break the feed.
  Future<({List<V2Topic> topics, DateTime fetchedAt})?> _safeCached() async {
    try {
      return await ref
          .read(v2exApiProvider)
          .feedCached(tab, maxAge: CacheTtl.feedFresh);
    } on Failure {
      return null;
    }
  }

  void _queueIdlePrefetch() {
    if (_prefetchQueued) return;
    _prefetchQueued = true;
    unawaited(prefetchNeighborFeeds(ref, tab));
  }
}

final feedProvider = AsyncNotifierProvider.family<FeedController, List<V2Topic>,
    HomeTab>(FeedController.new, retry: mv2Retry);

/// VXNA aggregator entries (`/xna`).
final xnaFeedProvider = FutureProvider<List<V2XnaEntry>>((ref) {
  return ref.watch(v2exApiProvider).xna();
}, retry: mv2Retry);
