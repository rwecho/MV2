import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/cache_ttl.dart';
import 'package:mv2/core/data/home_tab.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/core/telemetry/mv2_analytics.dart';
import 'package:mv2/core/telemetry/mv2_events.dart';
import 'package:mv2/features/feed/application/feed_providers.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/node_visuals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fixture_api.dart';

V2Topic _topic(String title) => V2Topic(
  id: title.hashCode,
  node: NodeVisuals.node(key: 'qna', name: '问与答'),
  title: title,
  author: V2User(username: 'livid'),
  createdAtLabel: '1 小时前',
  replyCount: 0,
);

/// Fixture api with a fake "disk cache" (the [seed] map) and call recording,
/// so the SWR flow — cache first, background revalidate, forced refresh — is
/// observable without a real cache or network.
class _SwrApi extends FixtureV2exApi {
  _SwrApi() : super(latency: Duration.zero);

  final Map<HomeTab, ({List<V2Topic> topics, DateTime fetchedAt})> seed =
      <HomeTab, ({List<V2Topic> topics, DateTime fetchedAt})>{};

  /// Network feed priorities per tab, in call order.
  final Map<HomeTab, List<PacePriority>> networkFeeds =
      <HomeTab, List<PacePriority>>{};

  /// When non-null, every network feed call throws this instead.
  Object? feedError;

  List<V2Topic> _networkTopics(String label) =>
      <V2Topic>[_topic('网络 $label')];

  @override
  Future<List<V2Topic>> feed(
    HomeTab tab, {
    PacePriority priority = PacePriority.userRead,
  }) async {
    final error = feedError;
    if (error != null) throw error;
    networkFeeds.putIfAbsent(tab, () => <PacePriority>[]).add(priority);
    return _networkTopics(tab.slug);
  }

  @override
  Future<({List<V2Topic> topics, DateTime fetchedAt})?> feedCached(
    HomeTab tab, {
    required Duration maxAge,
  }) async {
    final entry = seed[tab];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) > maxAge) return null;
    return entry;
  }
}

/// Same as [_SwrApi] but with real network latency, so the moment the cached
/// list is served — before revalidation finishes — is observable.
class _SlowNetworkApi extends _SwrApi {
  @override
  Future<List<V2Topic>> feed(
    HomeTab tab, {
    PacePriority priority = PacePriority.userRead,
  }) async {
    final error = feedError;
    if (error != null) throw error;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    networkFeeds.putIfAbsent(tab, () => <PacePriority>[]).add(priority);
    return _networkTopics(tab.slug);
  }
}

ProviderContainer _container(_SwrApi api) {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return ProviderContainer(
    overrides: [v2exApiProvider.overrideWithValue(api)],
  );
}

Future<void> _poll(
  bool Function() condition, {
  String reason = 'condition not met',
}) async {
  const timeout = Duration(seconds: 5);
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail(reason);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final analytics = <(String, Map<String, Object?>)>[];
  setUp(() {
    Mv2Analytics.sink = (event, params) => analytics.add((event, params));
  });
  tearDown(() {
    Mv2Analytics.sink = null;
    analytics.clear();
  });

  test('fresh cache renders first, then the network list swaps in', () async {
    final api = _SlowNetworkApi();
    api.seed[HomeTab.tech] = (
      topics: <V2Topic>[_topic('缓存')],
      fetchedAt: DateTime.now(),
    );
    final container = _container(api);
    addTearDown(container.dispose);

    // First frame: the cached list, served without waiting for the network.
    final first = await container.read(feedProvider(HomeTab.tech).future);
    expect(first.map((t) => t.title), <String>['缓存']);
    expect(api.networkFeeds[HomeTab.tech], isNull);

    // Revalidation lands moments later and replaces the list in place.
    await _poll(
      () =>
          container.read(feedProvider(HomeTab.tech)).value?.first.title ==
          '网络 tech',
    );

    expect(api.networkFeeds[HomeTab.tech]!.single, PacePriority.backgroundRead);
    expect(
      analytics.map((e) => e.$1),
      containsAll(<String>[Mv2Events.feedCacheHit, Mv2Events.feedRevalidate]),
    );
  });

  test('a cache entry past the freshness window is never shown', () async {
    final api = _SwrApi();
    api.seed[HomeTab.tech] = (
      topics: <V2Topic>[_topic('过期缓存')],
      fetchedAt: DateTime.now().subtract(
        CacheTtl.feedFresh + const Duration(minutes: 5),
      ),
    );
    final container = _container(api);
    addTearDown(container.dispose);

    final topics = await container.read(feedProvider(HomeTab.tech).future);

    expect(topics.map((t) => t.title), <String>['网络 tech']);
    expect(api.networkFeeds[HomeTab.tech], isNotNull);
    expect(
      analytics.map((e) => e.$1),
      isNot(contains(Mv2Events.feedCacheHit)),
    );
  });

  test('with no cache the feed loads straight from the network', () async {
    final api = _SwrApi();
    final container = _container(api);
    addTearDown(container.dispose);

    final topics = await container.read(feedProvider(HomeTab.tech).future);

    expect(topics.map((t) => t.title), <String>['网络 tech']);
    expect(api.networkFeeds[HomeTab.tech]!.single, PacePriority.userRead);
  });

  test('a revalidation failure keeps the cached list on screen', () async {
    final api = _SlowNetworkApi();
    api.seed[HomeTab.tech] = (
      topics: <V2Topic>[_topic('缓存')],
      fetchedAt: DateTime.now(),
    );
    api.feedError = const ParseFailure('revalidate fixture');
    final container = _container(api);
    addTearDown(container.dispose);

    await container.read(feedProvider(HomeTab.tech).future);
    await _poll(
      () => analytics.any((e) => e.$1 == Mv2Events.feedRevalidate),
      reason: 'revalidation never completed',
    );

    final state = container.read(feedProvider(HomeTab.tech));
    expect(state.hasValue, isTrue);
    expect(state.value!.map((t) => t.title), <String>['缓存']);
    expect(
      analytics
          .where((e) => e.$1 == Mv2Events.feedRevalidate)
          .single
          .$2['result'],
      'error',
    );
  });

  test('pull-to-refresh bypasses the cache and forces the network', () async {
    final api = _SwrApi();
    api.seed[HomeTab.tech] = (
      topics: <V2Topic>[_topic('缓存')],
      fetchedAt: DateTime.now(),
    );
    final container = _container(api);
    addTearDown(container.dispose);

    await container.read(feedProvider(HomeTab.tech).future);
    await _poll(() => api.networkFeeds[HomeTab.tech] != null);

    await container.read(feedProvider(HomeTab.tech).notifier).refresh();

    expect(api.networkFeeds[HomeTab.tech], hasLength(2));
    expect(
      container.read(feedProvider(HomeTab.tech)).value!.map((t) => t.title),
      <String>['网络 tech'],
    );
  });

  test('idle prefetch warms the neighbor tab in the background', () async {
    final api = _SwrApi();
    final container = _container(api);
    addTearDown(container.dispose);

        await container.read(feedProvider(HomeTab.tech).future);
    // The prefetch is queued) once the tab's own feed is ready; the neighbor
    // (creative, next in PageView order) must arrive as a background read.
    await _poll(() => api.networkFeeds[HomeTab.creative] != null);

    expect(
      api.networkFeeds[HomeTab.creative]!.single,
      PacePriority.backgroundRead,
    );
  });

  test('idle prefetch skips tabs whose cache is still fresh', () async {
    final api = _SwrApi();
    api.seed[HomeTab.creative] = (
      topics: <V2Topic>[_topic('缓存')],
      fetchedAt: DateTime.now(),
    );
    final container = _container(api);
    addTearDown(container.dispose);

    await container.read(feedProvider(HomeTab.tech).future);
    await _poll(() => api.networkFeeds[HomeTab.tech] != null);
    // Give the prefetcher a beat to (not) act on the fresh neighbor.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(api.networkFeeds[HomeTab.creative], isNull);
  });
}
