import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/home_tab.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/network/mv2_http_client.dart';

/// Live smoke test — **skipped by default**.
///
/// It exercises the real transport (cookie jar, pacing, manual redirects) and
/// the real parsers against `www.v2ex.com`. Run it explicitly:
///
/// ```bash
/// flutter test test/live_smoke_test.dart \
///   --dart-define=MV2_PROXY=http://127.0.0.1:7897
/// ```
///
/// Without `MV2_PROXY` the test is skipped so `flutter test` stays offline and
/// deterministic.
const String _proxy = String.fromEnvironment('MV2_PROXY');

void main() {
  final api = RemoteV2exApi(
    Mv2HttpClient.create(proxyUrl: _proxy.isEmpty ? null : _proxy),
  );

  test('home feed parses live markup', () async {
    final topics = await api.feed(HomeTab.tech);

    expect(topics, isNotEmpty);
    for (final topic in topics.take(5)) {
      expect(topic.id, greaterThan(0));
      expect(topic.title, isNotEmpty);
      expect(topic.node.name, isNotEmpty);
      expect(topic.author.username, isNotEmpty);
      expect(topic.createdAtLabel, isNotEmpty);
      expect(topic.node.name, isNot(equals(topic.createdAtLabel)));
    }
  }, skip: _proxy.isEmpty ? 'set --dart-define=MV2_PROXY=<proxy>' : null);

  test('the tab row parses for every topic tab', () async {
    for (final tab in HomeTab.values.where((t) => !t.isAggregator)) {
      expect(
        await api.feed(tab),
        isNotEmpty,
        reason: 'tab ${tab.slug} (${tab.label}) should have topics',
      );
    }
  }, skip: _proxy.isEmpty ? 'set --dart-define=MV2_PROXY=<proxy>' : null);

  test('VXNA parses external aggregator entries', () async {
    final entries = await api.xna();
    expect(entries, isNotEmpty);
    for (final entry in entries.take(5)) {
      expect(entry.title, isNotEmpty);
      expect(entry.url, startsWith('http'));
      expect(entry.sourceName, isNotEmpty);
    }
  }, skip: _proxy.isEmpty ? 'set --dart-define=MV2_PROXY=<proxy>' : null);

  test('topic detail parses header, body and replies', () async {
    final feed = await api.feed(HomeTab.tech);
    final detail = await api.topicDetail(feed.first.id);

    expect(detail.topic.title, isNotEmpty);
    expect(detail.topic.author.username, isNotEmpty);
    expect(detail.topic.createdAtLabel, isNotEmpty);
    expect(detail.contentHtml, isNotNull);
    expect(detail.replies, isNotEmpty);
    expect(detail.replies.first.author.username, isNotEmpty);
    expect(detail.replies.first.floor, 1);
  }, skip: _proxy.isEmpty ? 'set --dart-define=MV2_PROXY=<proxy>' : null);

  test('node feed and node list parse live markup', () async {
    final page = await api.nodePage('programmer');
    expect(page.topics, isNotEmpty);
    expect(page.topics.first.node.key, 'programmer');

    final nodes = await api.nodes();
    expect(nodes.length, greaterThan(100));
    final programmer = nodes.firstWhere((node) => node.key == 'programmer');
    expect(programmer.name, '程序员');
    expect(programmer.topicCount, greaterThan(1000));
  }, skip: _proxy.isEmpty ? 'set --dart-define=MV2_PROXY=<proxy>' : null);

  test('reply pagination walks to page 2 with a disjoint floor set', () async {
    // Find a topic with more than one page of replies.
    final hot = await api.feed(HomeTab.hot);
    final candidates = hot.where((topic) => topic.replyCount > 100);
    if (candidates.isEmpty) return;
    final target = candidates.first;

    final page1 = await api.topicDetail(target.id, page: 1);
    if (!page1.pagination.hasMore) return;
    final page2 = await api.topicDetail(target.id, page: 2);

    expect(page2.pagination.current, 2);
    expect(page2.replies, isNotEmpty);

    final floors1 = page1.replies.map((reply) => reply.floor).toSet();
    final floors2 = page2.replies.map((reply) => reply.floor).toSet();
    expect(floors1.intersection(floors2), isEmpty);
    expect(
      floors2.reduce((a, b) => a < b ? a : b),
      greaterThan(floors1.length),
    );
  }, skip: _proxy.isEmpty ? 'set --dart-define=MV2_PROXY=<proxy>' : null);

  test(
    'a signed-out session reports no account and no daily mission',
    () async {
      // `/` is public: the parser must not invent an account from the
      // signed-out shell.
      expect(await api.currentUser(), isNull);

      // `/mission/daily` redirects to /signin with an empty body; that must be
      // an auth failure, not an "already claimed" result.
      await expectLater(api.dailyMission(), throwsA(isA<AuthFailure>()));
    },
    skip: _proxy.isEmpty ? 'set --dart-define=MV2_PROXY=<proxy>' : null,
  );
}
