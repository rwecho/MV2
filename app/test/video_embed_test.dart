import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_rich_text.dart';
import 'package:mv2/ui/components/video_embed/mv2_video_embed.dart';
import 'package:mv2/ui/components/video_embed/mv2_video_embed_card.dart';

const String _hex64 =
    '7a92e17e33ab4314e6c25ddabec83eb919442b739bb83ab7285babf2ab57b884';

void main() {
  group('matchVideoEmbed — exe-hub', () {
    test('recognizes a Post link and plays it in place', () {
      final embed = matchVideoEmbed('https://hub.v2core.com/p/$_hex64');

      expect(embed, isNotNull);
      expect(embed!.provider, 'hub');
      expect(embed.playUrl.toString(), 'https://hub.v2core.com/p/$_hex64');
      expect(embed.needsRedirectResolution, isFalse);
    });

    test('rejects paths that are not a 64-hex Post id', () {
      expect(
        matchVideoEmbed('https://hub.v2core.com/p/not-a-post'),
        isNull,
      );
      expect(matchVideoEmbed('https://hub.v2core.com/p/abc123'), isNull);
      expect(matchVideoEmbed('https://hub.v2core.com/'), isNull);
    });
  });

  group('matchVideoEmbed — bilibili', () {
    test('BV video maps onto the clean embed player', () {
      final embed = matchVideoEmbed(
        'https://www.bilibili.com/video/BV1xx411c7mD?spm_id_from=333',
      );

      expect(embed, isNotNull);
      expect(embed!.provider, 'bilibili');
      expect(
        embed.playUrl.toString(),
        'https://player.bilibili.com/player.html?bvid=BV1xx411c7mD',
      );
      expect(embed.needsRedirectResolution, isFalse);
    });

    test('分P carries through as the player page', () {
      final embed = matchVideoEmbed(
        'https://www.bilibili.com/video/BV1xx411c7mD?p=2',
      );

      expect(
        embed!.playUrl.toString(),
        'https://player.bilibili.com/player.html?bvid=BV1xx411c7mD&page=2',
      );
    });

    test('m. host and legacy av numbers are recognized', () {
      expect(
        matchVideoEmbed('https://m.bilibili.com/video/BV1xx411c7mD')!.playUrl
            .toString(),
        'https://player.bilibili.com/player.html?bvid=BV1xx411c7mD',
      );
      expect(
        matchVideoEmbed('https://www.bilibili.com/video/av170001')!.playUrl
            .toString(),
        'https://player.bilibili.com/player.html?aid=170001',
      );
    });

    test('b23.tv short links are marked for redirect resolution', () {
      final embed = matchVideoEmbed('https://b23.tv/4gvVBLs');

      expect(embed, isNotNull);
      expect(embed!.provider, 'bilibili');
      expect(embed.needsRedirectResolution, isTrue);
    });

    test('non-video bilibili pages are ignored', () {
      expect(matchVideoEmbed('https://www.bilibili.com/v/popular/all'), isNull);
      expect(
        matchVideoEmbed('https://space.bilibili.com/1'),
        isNull,
      );
      expect(
        // BV ids are exactly 12 chars; a longer token is not an id.
        matchVideoEmbed('https://www.bilibili.com/video/BV1xx411c7mDxyz'),
        isNull,
      );
    });
  });

  group('matchVideoEmbed — youtube', () {
    test('watch / youtu.be / shorts all map onto the nocookie embed', () {
      for (final url in <String>[
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
      ]) {
        final embed = matchVideoEmbed(url);
        expect(embed, isNotNull, reason: url);
        expect(embed!.provider, 'youtube', reason: url);
        expect(
          embed.playUrl.toString(),
          'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
          reason: url,
        );
      }
    });

    test('rejects malformed ids and non-video pages', () {
      expect(matchVideoEmbed('https://www.youtube.com/watch'), isNull);
      expect(matchVideoEmbed('https://www.youtube.com/watch?v=short'), isNull);
      expect(matchVideoEmbed('https://www.youtube.com/feed/subscriptions'), isNull);
      expect(matchVideoEmbed('https://youtu.be/'), isNull);
    });
  });

  group('matchVideoEmbed — non-video links stay untouched', () {
    test('v2ex internal links, arbitrary sites and non-http schemes', () {
      expect(matchVideoEmbed('https://www.v2ex.com/t/1243480'), isNull);
      expect(matchVideoEmbed('https://v2core.com/p/$_hex64'), isNull);
      expect(matchVideoEmbed('https://example.com/video/BV1xx411c7mD'), isNull);
      expect(matchVideoEmbed('mv2://topic/123'), isNull);
      expect(matchVideoEmbed(null), isNull);
      expect(matchVideoEmbed(''), isNull);
    });
  });

  group('resolveVideoRedirect', () {
    test('follows the redirect off the short-link host', () async {
      final landed = await resolveVideoRedirect(
        Uri.parse('https://b23.tv/4gvVBLs'),
        fetchLocation: (url) async => (
          302,
          Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD/'),
        ),
      );

      expect(
        landed.toString(),
        'https://www.bilibili.com/video/BV1xx411c7mD/',
      );
    });

    test('returns the current URL when a hop has no Location', () async {
      final url = Uri.parse('https://b23.tv/4gvVBLs');
      final landed = await resolveVideoRedirect(
        url,
        fetchLocation: (url) async => (200, null),
      );

      expect(landed, url);
    });

    test('chains short-link → short-link → target', () async {
      final landed = await resolveVideoRedirect(
        Uri.parse('https://b23.tv/aaa'),
        fetchLocation: (url) async => switch (url.path) {
          '/aaa' => (302, Uri.parse('https://b23.tv/bbb')),
          _ => (302, Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD')),
        },
      );

      expect(landed!.host, 'www.bilibili.com');
    });

    test('gives up (null) after too many hops', () async {
      final landed = await resolveVideoRedirect(
        Uri.parse('https://b23.tv/loop'),
        maxHops: 5,
        fetchLocation: (url) async => (302, Uri.parse('https://b23.tv/loop-$url')),
      );

      expect(landed, isNull);
    });

    test('non-short-link URLs pass through untouched', () async {
      final url = Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD');
      var fetched = false;
      final landed = await resolveVideoRedirect(
        url,
        fetchLocation: (url) async {
          fetched = true;
          return (302, null);
        },
      );

      expect(landed, url);
      expect(fetched, isFalse);
    });
  });

  testWidgets('rich text upgrades video links to cards, ordinary links stay',
      (tester) async {
    Future<void> pump(String html) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: Mv2ThemeData.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 320, child: Mv2RichText(html: html)),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pump(
      '<p>视频在 <a href="https://hub.v2core.com/p/$_hex64">Mac OS 9 模拟</a> '
      '和 <a href="https://www.v2ex.com/t/1">站内帖</a>。</p>',
    );

    expect(find.byType(Mv2VideoEmbedCard), findsOneWidget);
    expect(find.text('Mac OS 9 模拟'), findsOneWidget);
    expect(find.text('exe-hub'), findsOneWidget);
    // The ordinary link stays rendered as inline text, not swallowed by the
    // card upgrade.
    expect(find.textContaining('站内帖'), findsOneWidget);
  });
}
