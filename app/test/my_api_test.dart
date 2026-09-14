import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/my/application/my_providers.dart';
import 'package:mv2/features/my/data/my_api.dart';
import 'package:mv2/features/my/presentation/my_topic_list_page.dart';

/// 我的 feature tests against **real captured signed-in markup**.
///
/// The `/my/*` and `/member/{u}/…` pages need the session cookie, which lives in
/// the app's keychain, so `curl` cannot fetch them. The fixtures under
/// `test/fixtures/` are trimmed copies of pages captured **through the running
/// app** (see the debug dump in `my_api.dart`) on 2026-09-11:
///
/// * `my_topics_real.html` — `/my/topics` (收藏主题), title `我收藏的主题`
/// * `my_member_topics_real.html` — `/member/rwecho/topics` (我的主题)
/// * `my_replies_real.html` — `/member/rwecho/replies` (我的回复)
/// * `my_nodes_real.html` — `/my/nodes` (我的节点)
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// Serves canned bodies for exact paths and records every request, so a test
/// can assert both the parsed result and the endpoint actually used.
class _FakeHttpClient extends Mv2HttpClient {
  _FakeHttpClient(this.responses) : super(Dio(), CookieJar());

  final Map<String, String> responses;
  final List<String> requested = <String>[];
  final List<String?> referers = <String?>[];

  @override
  Future<HttpResult> get(
    String path, {
    Map<String, dynamic>? query,
    String? referer,
    String? baseUrl,
  }) async {
    requested.add(path);
    referers.add(referer);
    final body = responses[path];
    if (body == null) {
      return const HttpResult(
        statusCode: 404,
        body: 'no fixture',
        headers: <String, List<String>>{},
      );
    }
    return HttpResult(
      statusCode: 200,
      body: body,
      headers: const <String, List<String>>{},
    );
  }
}

void main() {
  group('MyApi — real signed-in markup', () {
    test('收藏 (/my/topics) parses the favourite-topic list + pager', () async {
      final client = _FakeHttpClient(<String, String>{
        '/my/topics': fixture('my_topics_real.html'),
      });
      final api = MyApi(client, username: 'rwecho');

      final page = await api.favoriteTopics();

      expect(client.requested, <String>['/my/topics']);
      expect(client.referers.single, 'https://www.v2ex.com/my/');
      expect(page.topics, hasLength(3));
      expect(page.topics.first.id, 1174379);
      expect(page.topics.first.title, '独立开发者使用 cf r2 做图床视频床怎么样？');
      expect(page.topics.first.node.key, 'programmer');
      expect(page.topics.first.replyCount, 31);
      expect(page.pagination.current, 1);
      expect(page.pagination.maximum, 13);
    });

    test('我的主题 (/member/{u}/topics) parses the member topic list', () async {
      final client = _FakeHttpClient(<String, String>{
        '/member/rwecho/topics': fixture('my_member_topics_real.html'),
      });
      final api = MyApi(client, username: 'rwecho');

      final page = await api.myTopics();

      expect(client.requested, <String>['/member/rwecho/topics']);
      expect(page.topics, hasLength(3));
      expect(page.topics.first.id, 1235393);
      expect(page.topics.first.title, 'deepseek harness 手机端，各位有什么建议吗？');
      expect(page.topics.first.node.name, '分享创造');
      expect(page.pagination.maximum, greaterThan(1));
    });

    test('我的回复 (/member/{u}/replies) parses dock_area entries', () async {
      final client = _FakeHttpClient(<String, String>{
        '/member/rwecho/replies': fixture('my_replies_real.html'),
      });
      final api = MyApi(client, username: 'rwecho');

      final page = await api.myReplies();

      expect(client.requested, <String>['/member/rwecho/replies']);
      expect(page.topics, hasLength(3));
      final first = page.topics.first;
      expect(first.id, 1219824);
      expect(first.title, contains('做了 iOS / Android / 鸿蒙三端'));
      expect(first.author.username, isNotEmpty);
      expect(first.createdAtLabel, isNotEmpty);
      expect(first.excerpt, isNotNull);
      expect(page.pagination.maximum, 49);
    });

    test('我的节点 (/my/nodes) reads name + topic count per fav-node', () async {
      final client = _FakeHttpClient(<String, String>{
        '/my/nodes': fixture('my_nodes_real.html'),
      });
      final api = MyApi(client, username: 'rwecho');

      final nodes = await api.favoriteNodes();

      expect(client.requested, <String>['/my/nodes']);
      expect(nodes, hasLength(3));
      expect(nodes[0].key, 'v2ex');
      expect(nodes[0].name, 'V2EX');
      expect(nodes[0].topicCount, 4166);
      expect(nodes[2].key, 'vps');
      expect(nodes[2].name, 'VPS');
      expect(nodes[2].topicCount, 8305);
    });
  });

  group('MyApi — signed out', () {
    test('member-scoped lists return empty without a request', () async {
      final client = _FakeHttpClient(const <String, String>{});
      final api = MyApi(client); // username == null

      expect((await api.myTopics()).topics, isEmpty);
      expect((await api.myReplies()).topics, isEmpty);
      expect(client.requested, isEmpty);
    });
  });

  group('My providers — signed out', () {
    test(
      'every list provider is empty and never touches the network',
      () async {
        final client = _FakeHttpClient(<String, String>{
          '/my/topics': fixture('my_topics_real.html'),
          '/my/nodes': fixture('my_nodes_real.html'),
          '/member/rwecho/topics': fixture('my_member_topics_real.html'),
          '/member/rwecho/replies': fixture('my_replies_real.html'),
        });
        final container = ProviderContainer(
          overrides: [
            isSignedInProvider.overrideWith((ref) => false),
            myApiProvider.overrideWithValue(MyApi(client, username: 'rwecho')),
          ],
        );
        addTearDown(container.dispose);

        expect((await container.read(myTopicsProvider.future)).topics, isEmpty);
        expect(
          (await container.read(myRepliesProvider.future)).topics,
          isEmpty,
        );
        expect(
          (await container.read(favoriteTopicsProvider.future)).topics,
          isEmpty,
        );
        expect(await container.read(favoriteNodesProvider.future), isEmpty);
        expect(client.requested, isEmpty);
      },
    );
  });

  group('MyListKind labels', () {
    test('each kind owns its title and empty copy', () {
      for (final kind in MyListKind.values) {
        expect(kind.title, isNotEmpty);
        expect(kind.emptyTitle, isNotEmpty);
        expect(kind.emptyDescription, isNotEmpty);
      }
    });
  });
}
