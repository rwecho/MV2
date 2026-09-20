import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/home_tab.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/core/network/v2ex_endpoints.dart';
import 'package:mv2/core/parser/v1_json_parser.dart';

/// Records every request and replays canned responses (same harness as
/// `network_test.dart`).
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final FutureOr<ResponseBody> Function(RequestOptions options) responder;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _html(String body) => ResponseBody.fromString(
  body,
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
  },
);

Mv2HttpClient _clientWith(_FakeAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: V2exEndpoints.baseUrl,
      followRedirects: false,
      validateStatus: (status) => status != null && status < 400,
      headers: <String, String>{'User-Agent': V2exEndpoints.userAgent},
    ),
  )..httpClientAdapter = adapter;
  return Mv2HttpClient(dio, CookieJar());
}

/// v1 JSON API 的解析与「官方优先、页面解析兜底」的接线。
///
/// 字段形状按 2026-09 线上真实响应固化（latest.json 带 last_reply_by，
/// members/show.json 带 created 秒级时间戳）。
Map<String, Object?> _topicJson({
  int id = 1,
  String title = '官方接口提速',
  String? lastReplyBy = 'replier',
  int replies = 3,
}) {
  return <String, Object?>{
    'id': id,
    'title': title,
    'content': 'body',
    'content_rendered': '<p>body</p>',
    'replies': replies,
    'created': 1789889718,
    'last_modified': 1789889718,
    'last_touched': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 300,
    'last_reply_by': lastReplyBy,
    'member': <String, Object?>{
      'id': 440096,
      'username': 'phinex',
      'avatar_normal': '//cdn.v2ex.com/avatar/543f/dffd/440096_normal.png',
      'avatar_large': '//cdn.v2ex.com/avatar/543f/dffd/440096_large.png',
    },
    'node': <String, Object?>{
      'id': 12,
      'name': 'qna',
      'title': '问与答',
      'avatar_normal': '//cdn.v2ex.com/avatar/node/12.png',
    },
  };
}

void main() {
  group('V1JsonParser.parseTopicList', () {
    test('maps feed rows; last_reply_by wins over the topic author', () {
      final topics = V1JsonParser.parseTopicList(<Object?>[
        _topicJson(),
        _topicJson(id: 2, title: '无回复', lastReplyBy: null, replies: 0),
        'garbage',
      ]);

      expect(topics, hasLength(2));
      expect(topics.first.id, 1);
      expect(topics.first.title, '官方接口提速');
      expect(topics.first.author.username, 'replier');
      expect(topics.first.replyCount, 3);
      expect(topics.first.node.key, 'qna');
      expect(topics.first.node.name, '问与答');
      expect(topics.first.node.nodeId, 12);
      expect(topics.first.createdAtLabel, '5 分钟前');

      // 无回复时展示主题作者（头像可用）。
      expect(topics[1].author.username, 'phinex');
      expect(topics[1].author.avatarUrl, isNotNull);
    });

    test('non-list payloads degrade to an empty list', () {
      expect(V1JsonParser.parseTopicList(<String, Object?>{}), isEmpty);
      expect(V1JsonParser.parseTopicList(null), isEmpty);
    });

    test('relativeTime buckets', () {
      int unix(int secondsAgo) =>
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - secondsAgo;
      expect(V1JsonParser.relativeTime(unix(10)), '刚刚');
      expect(V1JsonParser.relativeTime(unix(5 * 60)), '5 分钟前');
      expect(V1JsonParser.relativeTime(unix(3 * 3600)), '3 小时前');
      expect(V1JsonParser.relativeTime(unix(2 * 86400)), '2 天前');
      expect(
        V1JsonParser.relativeTime(unix(120 * 86400)),
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      );
      expect(V1JsonParser.relativeTime(null), '');
    });
  });

  group('V1JsonParser.parseProfile', () {
    test('members/show.json → profile; counters stay null', () {
      final profile = V1JsonParser.parseProfile(<String, Object?>{
        'id': 1,
        'username': 'Livid',
        'tagline': 'Remember the bigger green',
        'created': 1272203146,
        'avatar_normal': '//cdn.v2ex.com/avatar/1_normal.png',
      });

      expect(profile, isNotNull);
      expect(profile!.user.username, 'Livid');
      expect(profile.user.tagline, 'Remember the bigger green');
      // 与实现同源换算，避免时区漂移。
      final created = DateTime.fromMillisecondsSinceEpoch(1272203146 * 1000);
      final mm = created.month.toString().padLeft(2, '0');
      final dd = created.day.toString().padLeft(2, '0');
      expect(profile.joinedAtLabel, '${created.year}-$mm-$dd');
      expect(profile.topicCount, isNull);
      expect(profile.replyCount, isNull);
    });

    test('unknown member defers to the HTML fallback', () {
      expect(
        V1JsonParser.parseProfile(<String, Object?>{
          'message': 'member_not_found',
        }),
        isNull,
      );
    });
  });

  group('RemoteV2exApi.feed — official JSON first, HTML fallback', () {
    late _FakeAdapter adapter;
    late RemoteV2exApi api;

    ResponseBody jsonBody(Object? payload, {int status = 200}) =>
        ResponseBody.fromString(
          jsonEncode(payload),
          status,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );

    test('hot tab serves hot.json and never touches the page', () async {
      adapter = _FakeAdapter((options) async => jsonBody(<Object?>[_topicJson()]));
      api = RemoteV2exApi(_clientWith(adapter));

      final topics = await api.feed(HomeTab.hot);

      expect(topics, hasLength(1));
      expect(adapter.requests.map((r) => r.uri.path), [
        V2exEndpoints.apiHotTopics,
      ]);
    });

    test('all tab falls back to the page when latest.json fails', () async {
      final feedHtml = File('test/fixtures/feed_real.html').readAsStringSync();
      adapter = _FakeAdapter((options) async {
        if (options.uri.path == V2exEndpoints.apiLatestTopics) {
          return ResponseBody.fromString('boom', 500);
        }
        return _html(feedHtml);
      });
      api = RemoteV2exApi(_clientWith(adapter));

      final topics = await api.feed(HomeTab.all);

      expect(topics, isNotEmpty);
      // `?tab=all` 是 query 参数，不在 path 里。
      expect(adapter.requests.map((r) => r.uri.toString()), [
        'https://www.v2ex.com/api/topics/latest.json',
        'https://www.v2ex.com/?tab=all',
      ]);
    });

    test('tabs without an official endpoint scrape directly', () async {
      final feedHtml = File('test/fixtures/feed_real.html').readAsStringSync();
      adapter = _FakeAdapter((options) async => _html(feedHtml));
      api = RemoteV2exApi(_clientWith(adapter));

      final topics = await api.feed(HomeTab.r2);

      expect(topics, isNotEmpty);
      expect(adapter.requests.map((r) => r.uri.toString()), [
        'https://www.v2ex.com/?tab=r2',
      ]);
    });
  });
}
