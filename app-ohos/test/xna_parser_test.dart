import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/home_tab.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/parser/xna_parser.dart';

/// Parser regression tests against the **real** `/xna` capture.
///
/// `xna_real.html` is a trimmed copy of `https://www.v2ex.com/xna` fetched on
/// 2026-09-11 (4 aggregator entries), see `docs/12-v2ex-api-inventory.md`.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  // `FixtureV2exApi` reads the packaged `assets/fixtures/` through `rootBundle`.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('XnaParser — /xna (real markup)', () {
    test('parses every real entry', () {
      final entries = XnaParser.parse(fixture('xna_real.html'));

      expect(entries, hasLength(4));
      for (final entry in entries) {
        expect(entry.title, isNotEmpty);
        expect(entry.url, startsWith('http'));
        expect(entry.sourceName, isNotEmpty);
      }
    });

    test('reads the external url, source and member', () {
      final first = XnaParser.parse(fixture('xna_real.html')).first;

      expect(first.title, '摘：《说灵魂》');
      expect(
        first.url,
        'https://z.arlmy.me/posts/Note/Note_ChengBaoYi_ShuoLingHun/',
      );
      expect(first.sourceName, '素生');
      expect(first.sourceUrl, 'https://z.arlmy.me/');
      expect(first.author?.username, 'arlmy');
      expect(first.author?.avatarUrl, startsWith('https://cdn.v2ex.com/'));
      expect(first.timeLabel, '4 小时 0 分钟前');
    });

    test('never treats the external link as an on-site topic', () {
      final entries = XnaParser.parse(fixture('xna_real.html'));
      for (final entry in entries) {
        expect(entry.url, isNot(contains('www.v2ex.com/t/')));
      }
    });

    test('returns an empty list on an unknown page', () {
      expect(XnaParser.parse('<html><body>nope</body></html>'), isEmpty);
    });
  });

  group('FixtureV2exApi home tabs', () {
    test('xna() serves the bundled /xna asset', () async {
      final entries = await FixtureV2exApi(latency: Duration.zero).xna();

      expect(entries, hasLength(4));
      expect(entries.first.url, startsWith('https://'));
      expect(entries.first.sourceName, isNotEmpty);
    });

    test('feed() serves a topic list for every topic tab', () async {
      final api = FixtureV2exApi(latency: Duration.zero);

      for (final tab in HomeTab.values.where((t) => !t.isAggregator)) {
        expect(
          await api.feed(tab),
          isNotEmpty,
          reason: 'fixture feed for ${tab.name}',
        );
      }
      // The aggregator is never a topic list.
      expect(await api.feed(HomeTab.vxna), isEmpty);
    });
  });
}
