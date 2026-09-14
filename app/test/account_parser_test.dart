import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/parser/account_parser.dart';

/// Parser regression tests for the signed-in account / daily mission path.
///
/// Both fixtures are labelled **synthetic**: the live pages require a session
/// (`/` hides the avatar sidebar anonymously, `/mission/daily` answers
/// `302 → /signin`) and this project has no V2EX account. They follow the
/// `docs/12` §UserInfo / §DailyInfo DOM contract that the parsers implement.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('AccountParser.parseCurrentUser — synthetic signed-in #Rightbar', () {
    test('reads username, avatar, member id, notifications and money', () {
      final info = AccountParser.parseCurrentUser(
        fixture('account_signed_in.html'),
      );

      expect(info, isNotNull);
      expect(info!.user.username, 'rwecho');
      expect(info.user.id, 94728);
      expect(
        info.user.avatarUrl,
        'https://cdn.v2ex.com/avatar/a1b2/c3d4/94728_large.png?m=1789110000',
      );
      expect(info.notifications, '3');
      expect(info.moneyGold, '9.6');
      expect(info.moneySilver, '120');
      expect(info.moneyBronze, '0');
    });

    test('reads the unread count from the live flex-one-row row', () {
      final info = AccountParser.parseCurrentUser(
        '<html><body><div id="Rightbar"><div class="box">'
        '<img class="avatar" src="//cdn.v2ex.com/avatar/a.png" alt="rwecho" />'
        '<div class="cell flex-one-row">'
        '<a href="/notifications">3 条未读提醒</a>'
        '</div></div></div></body></html>',
      );

      expect(info, isNotNull);
      expect(info!.notifications, '3 条未读提醒');
      expect(info.user.username, 'rwecho');
    });

    test(
      'falls back to the member anchor and 第 N 号 when data-uid is absent',
      () {
        final info = AccountParser.parseCurrentUser(
          '<html><body><div id="Rightbar"><div class="cell">'
          '<img class="avatar" src="//cdn.v2ex.com/avatar/a.png" alt="" />'
          '<a href="/member/rwecho">rwecho</a>'
          '<span class="fade">V2EX 第 94728 号会员</span>'
          '</div></div></body></html>',
        );

        expect(info, isNotNull);
        expect(info!.user.username, 'rwecho');
        expect(info.user.id, 94728);
        // Protocol-relative avatar URLs are normalised to https.
        expect(info.user.avatarUrl, 'https://cdn.v2ex.com/avatar/a.png');
      },
    );

    test('returns null for the anonymous shell (no #Rightbar avatar)', () {
      expect(
        AccountParser.parseCurrentUser(
          '<html><body><div id="Rightbar"><div class="box">'
          '已注册用户请 <a href="/signin">登录</a>'
          '</div></div></body></html>',
        ),
        isNull,
      );
    });

    test('returns null when there is no sidebar at all', () {
      expect(
        AccountParser.parseCurrentUser('<html><body>nope</body></html>'),
        isNull,
      );
    });
  });

  group('DailyMissionParser.parse — synthetic /mission/daily', () {
    test('reads the streak label and the redeem path', () {
      final mission = DailyMissionParser.parse(fixture('daily_mission.html'));

      expect(mission.continuousDaysLabel, '已连续登录 12 天');
      expect(mission.redeemPath, '/mission/daily/redeem?once=55555');
      expect(mission.alreadyCheckedIn, isFalse);
    });

    test('marks the bonus claimed when no redeem button is present', () {
      final mission = DailyMissionParser.parse(
        '<html><body><div class="cell"><span>已连续登录 12 天</span></div></body></html>',
      );

      expect(mission.continuousDaysLabel, '已连续登录 12 天');
      expect(mission.redeemPath, isNull);
      expect(mission.alreadyCheckedIn, isTrue);
    });
  });
}
