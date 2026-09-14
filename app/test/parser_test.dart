import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/parser/feed_parser.dart';
import 'package:mv2/core/parser/node_parser.dart';
import 'package:mv2/core/parser/topic_parser.dart';

/// Parser regression tests against **real captured markup**.
///
/// `feed_real.html`, `topic_real.html` and `node_real.html` are trimmed copies
/// of pages fetched from `www.v2ex.com` on 2026-09-11 (see
/// `docs/12-v2ex-api-inventory.md`). `topic_detail_logged_in.html` is the same
/// real page with the signed-in markup (`once`, 收藏/感谢/忽略 buttons)
/// injected, because live pages only render those for authenticated sessions.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('FeedParser — home/recent (real markup)', () {
    test('parses every real item', () {
      final topics = FeedParser.parseTopicList(fixture('feed_real.html'));

      expect(topics, hasLength(3));
      for (final topic in topics) {
        expect(topic.id, greaterThan(0));
        expect(topic.title, isNotEmpty);
        expect(topic.node.name, isNotEmpty);
        expect(topic.author.username, isNotEmpty);
        expect(topic.createdAtLabel, isNotEmpty);
      }
    });

    test('reads node, author, relative time and the sibling reply count', () {
      final first = FeedParser.parseTopicList(fixture('feed_real.html')).first;

      expect(first.id, 1241200);
      expect(first.title, '周五了，额度双双用光光');
      expect(first.node.key, 'programmer');
      expect(first.node.name, '程序员');
      expect(first.author.username, 'tongyuelong');
      // The relative time lives in `span[title]`, NOT in the text before the
      // author `<strong>` (that slot holds the node link).
      expect(first.createdAtLabel, '几秒前');
      // The count anchor is in a sibling `<td width="70">`.
      expect(first.replyCount, 20);
      expect(first.url, 'https://www.v2ex.com/t/1241200#reply20');
    });

    test('keeps the node in the node link, not in the time slot', () {
      final topics = FeedParser.parseTopicList(fixture('feed_real.html'));
      expect(topics[1].node.name, isNotEmpty);
      expect(topics[1].createdAtLabel, isNot(equals(topics[1].node.name)));
    });

    test('returns an empty list instead of throwing on an unknown page', () {
      expect(
        FeedParser.parseTopicList('<html><body>nope</body></html>'),
        isEmpty,
      );
    });
  });

  group('FeedParser — /go/{node} (real markup)', () {
    test('reads #TopicsNode items and the shared pager', () {
      final page = NodeParser.parseNodePage(
        fixture('node_real.html'),
        nodeName: 'programmer',
      );

      expect(page.topics, hasLength(2));
      expect(page.pagination.current, 1);
      expect(page.pagination.maximum, greaterThan(1));
      for (final topic in page.topics) {
        // Node pages omit the node link, so the caller-supplied node is used.
        expect(topic.node.key, 'programmer');
        expect(topic.title, isNotEmpty);
        expect(topic.replyCount, greaterThan(0));
      }
    });
  });

  group('TopicParser — /t/{id} (real markup)', () {
    test('parses header, body, tags and the reply stat line', () {
      final detail = TopicParser.parse(
        fixture('topic_real.html'),
        topicId: 1241298,
      );

      expect(
        detail.topic.title,
        'Anthropic 点名多家中国公司蒸馏 Claude，包括 Qwen, kimi, deepseek, glm, xiaomi, Minimax',
      );
      expect(detail.topic.node.key, 'programmer');
      expect(detail.topic.node.name, '程序员');
      expect(detail.topic.author.username, 'ensonfun');
      // `small > span[title]` inside the header.
      expect(detail.topic.createdAtLabel, '2 小时 23 分钟前');
      // `small` tail after the last `·`.
      expect(detail.statsLabel, '6600 次点击');

      expect(detail.contentHtml, contains('还公布了很多细节'));
      expect(detail.tags, contains('Anthropic'));
      expect(detail.replyStatsLabel, '169 条回复');
    });

    test('reads the real pager markup', () {
      final detail = TopicParser.parse(
        fixture('topic_real.html'),
        topicId: 1241298,
      );

      expect(detail.pagination.current, 1);
      expect(detail.pagination.maximum, 2);
      expect(detail.pagination.hasMore, isTrue);
    });

    test('parses replies from `div#r_*` cells', () {
      final detail = TopicParser.parse(
        fixture('topic_real.html'),
        topicId: 1241298,
      );

      expect(detail.replies, hasLength(3));
      expect(detail.replies.map((reply) => reply.floor), <int>[1, 2, 3]);
      for (final reply in detail.replies) {
        expect(reply.id, isNotNull);
        expect(reply.author.username, isNotEmpty);
        expect(reply.createdAtLabel, isNotEmpty);
        expect(reply.content, isNotEmpty);
      }
    });

    test('marks the topic author (楼主) from V2EX\'s own badge', () {
      final detail = TopicParser.parse(
        fixture('topic_real.html'),
        topicId: 1241298,
      );

      // V2EX renders `<div class="badge op">OP</div>` on the author's replies.
      final ownerReplies = detail.replies.where((reply) => reply.isOwner);
      expect(ownerReplies, isNotEmpty);
      expect(ownerReplies.first.badges, contains('OP'));
      expect(ownerReplies.first.author.username, detail.topic.author.username);
      // Non-author replies must not be flagged.
      expect(
        detail.replies.where((reply) => !reply.isOwner),
        isNotEmpty,
      );
    });

    test('a signed-out page carries no CSRF token or action state', () {
      final detail = TopicParser.parse(
        fixture('topic_real.html'),
        topicId: 1241298,
      );

      expect(detail.once, isNull);
      expect(detail.canReply, isFalse);
      expect(detail.favorited, isFalse);
      expect(detail.thanked, isFalse);
      expect(detail.ignored, isFalse);
    });

    test('reads once and the action state when signed in', () {
      final detail = TopicParser.parse(
        fixture('topic_detail_logged_in.html'),
        topicId: 1241298,
      );

      expect(detail.once, 'abc123');
      expect(detail.canReply, isTrue);
      expect(detail.favorited, isTrue);
      expect(detail.thanked, isTrue);
      expect(detail.ignored, isTrue);
    });

    test('throws ParseFailure when the page shape changed', () {
      expect(
        () => TopicParser.parse('<html><body></body></html>', topicId: 1),
        throwsA(isA<ParseFailure>()),
      );
    });
  });

  group('NodeParser — JSON endpoints', () {
    test('parses /api/nodes/s2.json ({text, id, topics, aliases})', () {
      final nodes = NodeParser.parseNodesJson(<dynamic>[
        <String, dynamic>{
          'text': '程序员 / programmer',
          'topics': 73281,
          'id': 'programmer',
          'aliases': <String>['developer'],
        },
        <String, dynamic>{
          'text': 'Apple / apple',
          'topics': 31119,
          'id': 'apple',
          'aliases': <String>[],
        },
      ]);

      expect(nodes, hasLength(2));
      expect(nodes.first.key, 'programmer');
      expect(nodes.first.name, '程序员');
      expect(nodes.first.topicCount, 73281);
      expect(nodes.first.tags, <String>['developer']);
      expect(nodes[1].name, 'Apple');
    });

    test('parses /api/topics/hot.json and strips HTML from content', () {
      final topics = NodeParser.parseHotTopicsJson(<dynamic>[
        <String, dynamic>{
          'id': 3001,
          'title': 'Hot topic',
          'url': 'https://www.v2ex.com/t/3001',
          'content': '<p>hello <b>world</b></p>',
          'replies': 12,
          'member': <String, dynamic>{'username': 'alice'},
          'node': <String, dynamic>{'name': 'programmer', 'title': '程序员'},
        },
      ]);

      expect(topics, hasLength(1));
      expect(topics.first.id, 3001);
      expect(topics.first.replyCount, 12);
      expect(topics.first.author.username, 'alice');
      expect(topics.first.excerpt, 'hello world');
    });
  });
}
