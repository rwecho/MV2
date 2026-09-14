import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/parser/member_parser.dart';
import 'package:mv2/core/parser/notification_parser.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/notification_page.dart';

/// Parser regression tests for the 通知 / 我的 data path.
///
/// `notifications_signed_in.html` is **synthetic** (documented in the fixture):
/// `/notifications` requires a session, answers `302 → /signin` anonymously and
/// therefore cannot be captured. It mirrors the documented item shape
/// (`div[id^="n_"]`, `td strong`, `td a img`, `a.topic-link`, `span.snow`,
/// `div.payload`). `member_livid.html` is a trimmed real capture of
/// `https://www.v2ex.com/member/Livid`.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// Minimal notification item used by the inline grouping tests.
String item(String id, String snow) =>
    '''
<div class="cell" id="n_$id">
  <table><tr>
    <td width="48"><a href="/member/alice"><img class="avatar" src="/avatar/alice.png" /></a></td>
    <td><strong><a href="/member/alice">alice</a></strong> 回复了你的主题
      <a href="/t/$id#reply1" class="topic-link">主题 $id</a>
      <div class="payload">hello $id</div>
      <span class="snow">$snow</span>
    </td>
  </tr></table>
</div>
''';

void main() {
  group('NotificationParser — synthetic signed-in markup', () {
    late NotificationPage page;

    setUpAll(() {
      page = NotificationParser.parse(fixture('notifications_signed_in.html'));
    });

    test('groups items by day (今天 / 昨天 / 更早)', () {
      expect(page.isSignedOut, isFalse);
      expect(page.groups.map((group) => group.title).toList(), <String>[
        '今天',
        '昨天',
        '更早',
      ]);
      expect(page.groups[0].items, hasLength(2));
      expect(page.groups[1].items, hasLength(1));
      expect(page.groups[2].items, hasLength(1));
      expect(page.items, hasLength(4));
    });

    test('reads the notification feed URL used for push registration', () {
      // The push worker polls this URL, so a missing or malformed value would
      // silently leave the device unregistered.
      expect(
        page.feedUrl,
        'https://www.v2ex.com/feed/notifications.xml?once=syntheticfixture0000',
      );
    });

    test('reads actor, avatar, topic title and href', () {
      final first = page.items.first;

      expect(first.id, '910001');
      expect(first.actor.username, 'kernel');
      expect(
        first.actor.avatarUrl,
        'https://cdn.v2ex.com/avatar/1a2b/3c4d/100001_large.png?m=1',
      );
      expect(first.sourceTitle, '周五了，额度双双用光光');
      expect(first.topicId, 1241200);
      expect(first.topicUrl, 'https://www.v2ex.com/t/1241200#reply20');
    });

    test('reads the quoted payload as plain text', () {
      final first = page.items.first;

      expect(first.quote, '我也遇到过类似的问题，后来通过调整提示词格式解决了，分享一下我的配置要点…');
      // The payload contains `@`; it must not reclassify the reply as a mention.
      expect(first.kind, NotificationKind.reply);
    });

    test('classifies the action kind', () {
      expect(page.items[1].kind, NotificationKind.mention);
      expect(page.items[2].kind, NotificationKind.like);
      expect(page.items[3].kind, NotificationKind.favorite);
    });

    test('reads the pager (current/max/hasMore)', () {
      expect(page.pagination.current, 1);
      expect(page.pagination.maximum, 3);
      expect(page.pagination.hasMore, isTrue);
    });

    test('reads span.snow time and the unread marker', () {
      expect(page.items[0].timeLabel, '3 小时前');
      expect(page.items[2].timeLabel, '1 天前');
      expect(page.items[0].isUnread, isTrue);
      expect(page.items[2].isUnread, isFalse);
    });
  });

  group('NotificationParser — grouping fallback (`span.snow`)', () {
    test('buckets relative and absolute labels when there is no separator', () {
      final html =
          '<html><body><div id="Wrapper">'
          '${item('1', '3 小时前')}'
          '${item('2', '1 天前')}'
          '${item('3', '8 月 1 日')}'
          '</div></body></html>';

      final page = NotificationParser.parse(html);

      expect(page.groups.map((group) => group.title).toList(), <String>[
        '今天',
        '昨天',
        '更早',
      ]);
      expect(page.groups[0].items.single.id, '1');
      expect(page.groups[1].items.single.id, '2');
      expect(page.groups[2].items.single.id, '3');
    });
  });

  group('NotificationParser — explicit day separators', () {
    test('separators win over the span.snow label', () {
      final html =
          '<html><body><div id="Wrapper">'
          '<div class="cell"><span class="fade">今天</span></div>'
          '${item('1', '8 月 1 日')}'
          '<div class="cell"><span class="fade">更早</span></div>'
          '${item('2', '3 小时前')}'
          '</div></body></html>';

      final page = NotificationParser.parse(html);

      expect(page.groups.map((group) => group.title).toList(), <String>[
        '今天',
        '更早',
      ]);
      expect(page.groups[0].items.single.id, '1');
      expect(page.groups[1].items.single.id, '2');
    });
  });

  group('NotificationParser — signed out / unknown pages', () {
    test('an empty body is an empty 1/1 page and does not throw', () {
      final page = NotificationParser.parse('');

      expect(page.groups, isEmpty);
      expect(page.pagination.current, 1);
      expect(page.pagination.maximum, 1);
      expect(page.isSignedOut, isTrue);
    });

    test('the sign-in shell is detected as signed out', () {
      final page = NotificationParser.parse(
        '<html><body><div id="Wrapper">'
        '<form action="/signin" method="post"></form>'
        '</div></body></html>',
      );

      expect(page.groups, isEmpty);
      expect(page.pagination.current, 1);
      expect(page.pagination.maximum, 1);
      expect(page.isSignedOut, isTrue);
    });

    test('an unknown page yields an empty list instead of throwing', () {
      expect(
        NotificationParser.parse('<html><body>nope</body></html>').items,
        isEmpty,
      );
    });

    test('a signed-in page with no items is not reported as signed out', () {
      final page = NotificationParser.parse(
        '<html><body><div id="Wrapper"><div class="cell">'
        '<span class="gray">没有未读提醒</span></div></div></body></html>',
      );

      expect(page.items, isEmpty);
      expect(page.isSignedOut, isFalse);
    });
  });

  group('MemberParser — real /member/Livid capture', () {
    late V2Profile? profile;

    setUpAll(() {
      profile = MemberParser.parseMemberPage(fixture('member_livid.html'));
    });

    test('reads username, member id, avatar and tagline', () {
      expect(profile, isNotNull);
      expect(profile!.user.username, 'Livid');
      expect(profile!.user.id, 1);
      expect(
        profile!.user.avatarUrl,
        'https://cdn.v2ex.com/avatar/c4ca/4238/1_xlarge.png?m=1786747568',
      );
      expect(profile!.user.tagline, 'Remember the bigger green');
    });

    test('the anonymous member page exposes no counters', () {
      // V2EX only shows `V2EX 第 N 号会员` publicly, so the counters stay null
      // and the profile page hides the whole stat strip rather than showing 0.
      expect(profile!.topicCount, isNull);
      expect(profile!.replyCount, isNull);
      expect(profile!.favoriteCount, isNull);
    });

    test('reads the join date from the member sentence', () {
      // `V2EX 第 1 号会员，加入于 2010-04-25 21:45:46 +08:00`
      expect(profile!.joinedAtLabel, '2010-04-25');
    });

    test('reads the recent topics', () {
      expect(profile!.recentTopics, hasLength(3));
      expect(profile!.recentTopics.first.id, 1239253);
      expect(
        profile!.recentTopics.first.title,
        '我给我的各种 agents 做了一个 social network',
      );
      expect(profile!.recentTopics.first.node.key, 'wunder');
    });

    test('falls back to the V2EX #<id> text when data-uid is absent', () {
      final parsed = MemberParser.parseMemberPage(
        '<html><body><div id="Wrapper"><div class="cell"><h1>rwecho</h1>'
        '<span class="gray">V2EX #94728</span></div></div></body></html>',
      );

      expect(parsed, isNotNull);
      expect(parsed!.user.username, 'rwecho');
      expect(parsed.user.id, 94728);
    });

    test('returns null when the page has no member header', () {
      expect(
        MemberParser.parseMemberPage('<html><body><p>nope</p></body></html>'),
        isNull,
      );
    });
  });
}
