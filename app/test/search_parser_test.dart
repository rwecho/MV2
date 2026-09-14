import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/parser/node_parser.dart';
import 'package:mv2/core/parser/search_parser.dart';
import 'package:mv2/shared/models/models.dart';

/// Parser regression tests against a **real captured** sov2ex response.
///
/// `search_sov2ex.json` is the live answer to
/// `GET https://www.sov2ex.com/api/search?q=codex&from=0&size=5&sort=created`
/// fetched on 2026-09-11, trimmed to its first three hits with the exact
/// envelope (`took` / `total` / `hits` / `timed_out`) preserved.
Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  group('SearchParser.parseSov2ex (real captured JSON)', () {
    late List<V2Topic> topics;

    setUp(() {
      topics = SearchParser.parseSov2ex(fixture('search_sov2ex.json'));
    });

    test('parses every hit in the trimmed capture', () {
      expect(topics, hasLength(3));
    });

    test('reads id, title, author and reply count from _source', () {
      final first = topics.first;

      expect(first.id, 1241319);
      expect(first.title, contains('CUBENCE'));
      expect(first.author.username, 'alynn');
      expect(first.replyCount, 0);
      expect(first.url, 'https://www.v2ex.com/t/1241319');
      expect(first.createdAtLabel, isNotEmpty);
    });

    test('exposes the numeric node id as the node key', () {
      final first = topics.first;
      // sov2ex returns only `node: 864`; the slug/name are not in the payload.
      expect(first.node.key, '864');
      expect(first.node.name, '节点 864');
      expect(first.node.nodeId, isNull);
    });

    test('resolves the numeric node id through the all-nodes directory', () {
      final directory = NodeParser.parseAllNodesJson(
        fixture('nodes_all_sample.json'),
      );
      final resolved = SearchParser.parseSov2ex(
        fixture('search_sov2ex.json'),
        directory: directory,
      );

      expect(resolved, hasLength(3));
      final first = resolved.first;
      expect(first.node.key, 'promotions');
      expect(first.node.name, '推广');
      expect(first.node.nodeId, 864);
      // The rest of the hit is untouched by the directory lookup.
      expect(first.id, 1241319);
      expect(first.title, contains('CUBENCE'));
      expect(first.excerpt, contains('Codex'));

      // Third hit is node 17, also present in the sample.
      expect(resolved[2].node.key, 'create');
      expect(resolved[2].node.name, '分享创造');
    });

    test('keeps the 节点 {id} fallback when the directory lacks the id', () {
      final directory = NodeParser.parseAllNodesJson(
        fixture('nodes_all_sample.json'),
      );
      final topics = SearchParser.parseSov2ex(
        fixture('search_sov2ex.json'),
        directory: directory,
      );

      // Hit 2 is node 69, which the trimmed 3-entry sample does not contain.
      expect(topics[1].node.key, '69');
      expect(topics[1].node.name, '节点 69');
      expect(topics[1].id, 1241312);
    });

    test('prefers the <em>-highlighted excerpt and strips inline markup', () {
      final first = topics.first;
      expect(first.excerpt, isNotNull);
      expect(first.excerpt, contains('Codex'));
      expect(first.excerpt, isNot(contains('<em>')));
    });

    test('falls back to the body when the hit has no content highlight', () {
      final second = topics[1];
      expect(second.id, 1241312);
      expect(second.author.username, 'glzcc520');
      expect(second.excerpt, contains('联系方式'));
    });

    test('throws ParseFailure — not a generic error — on malformed input', () {
      expect(
        () => SearchParser.parseSov2ex('not json at all'),
        throwsA(isA<ParseFailure>()),
      );
      expect(
        () => SearchParser.parseSov2ex(<String, dynamic>{'total': 1}),
        throwsA(isA<ParseFailure>()),
      );
      expect(
        () => SearchParser.parseSov2ex(<String, dynamic>{'hits': 'nope'}),
        throwsA(isA<ParseFailure>()),
      );
    });
  });

  group('SearchParser.parseSiteSearch', () {
    test('returns empty when the user section is missing', () {
      // Live `/search?q=` 302s to the `search` node page, whose member links are
      // topic authors — they must not be mistaken for search hits.
      const html = '''
        <html><body><div class="cell item">
          <a href="/member/trevor233ana">trevor233ana</a>
        </div></body></html>
      ''';
      expect(SearchParser.parseSiteSearch(html), isEmpty);
    });

    test('parses member anchors inside a dedicated user-result section', () {
      const html = '''
        <html><body>
          <ul class="user-list">
            <li><a href="/member/alice"><img src="//cdn.v2ex.com/a.png">alice</a></li>
            <li><a href="/member/bob">bob</a></li>
            <li><a href="/member/alice">alice</a></li>
          </ul>
        </body></html>
      ''';
      final users = SearchParser.parseSiteSearch(html);

      expect(users, hasLength(2));
      expect(users.first.username, 'alice');
      expect(users.first.avatarUrl, 'https://cdn.v2ex.com/a.png');
      expect(users[1].username, 'bob');
    });
  });

  /// `/api/nodes/all.json` is the only payload that carries BOTH a numeric node
  /// id and the slug, so it is what resolves sov2ex's `node: 864`.
  group('NodeParser.parseAllNodesJson (numeric id → node)', () {
    test('maps id → slug/title, trims aliases and skips malformed entries', () {
      // A 3-entry sample: one valid entry, one non-map, one valid entry.
      final nodes = NodeParser.parseAllNodesJson(<dynamic>[
        <String, dynamic>{
          'id': 300,
          'name': 'programmer',
          'title': '程序员',
          'topics': 73280,
          'aliases': <String>['developer', 'dev', 'coder', 'ignored'],
        },
        'not-a-map', // malformed: skipped
        <String, dynamic>{'id': 864, 'name': 'promotions', 'title': '推广'},
      ]);

      expect(nodes, hasLength(2));

      final programmer = nodes[300]!;
      expect(programmer.key, 'programmer');
      expect(programmer.name, '程序员');
      expect(programmer.nodeId, 300);
      expect(programmer.topicCount, 73280);
      // Trimmed to 3, matching the sibling `parseNodesJson`.
      expect(programmer.tags, <String>['developer', 'dev', 'coder']);

      final promotions = nodes[864]!;
      expect(promotions.key, 'promotions');
      expect(promotions.name, '推广');
      expect(promotions.nodeId, 864);
      expect(promotions.topicCount, isNull);
      expect(promotions.tags, isEmpty);
    });

    test('throws ParseFailure on a non-list payload', () {
      expect(
        () => NodeParser.parseAllNodesJson(<String, dynamic>{'nodes': 1}),
        throwsA(isA<ParseFailure>()),
      );
      expect(
        () => NodeParser.parseAllNodesJson('nope'),
        throwsA(isA<ParseFailure>()),
      );
    });

    test('parses the captured all.json sample', () {
      final nodes = NodeParser.parseAllNodesJson(
        fixture('nodes_all_sample.json'),
      );

      expect(nodes, hasLength(3));
      expect(nodes[864]!.key, 'promotions');
      expect(nodes[864]!.name, '推广');
      expect(nodes[300]!.name, '程序员');
      expect(nodes[300]!.topicCount, 73280);
      expect(nodes[17]!.nodeId, 17);
    });
  });
}
