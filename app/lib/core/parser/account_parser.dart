import 'package:html/dom.dart';

import '../../shared/models/account_info.dart';
import '../../shared/models/daily_mission.dart';
import '../../shared/models/models.dart';
import 'html_dom.dart';

/// Scrapes the signed-in account from a session page.
///
/// V2EX exposes "who am I" only through the right sidebar of an authenticated
/// page (`#Rightbar`), see the legacy `UserInfo` contract in `docs/12`. The
/// signed-out shell renders a 登录/注册 box instead, so the presence of an
/// avatar image is the sign-in signal.
///
/// Selectors are defensive on purpose: this is the one place we cannot verify
/// without a real account, so several fallbacks are chained and a miss returns
/// `null` rather than throwing.
abstract final class AccountParser {
  static V2AccountInfo? parseCurrentUser(String html) {
    final document = parseHtmlDocument(html);
    final sidebar = document.querySelector('div#Rightbar');
    if (sidebar == null) return null;

    // Signed-out pages render a `现在注册 / 登录` box in the sidebar. That link
    // is the reliable signal — the sidebar also contains member links and
    // avatars in other boxes, which used to produce a false positive.
    if (sidebar.querySelector('a[href="/signup"]') != null) return null;

    // The account box is the first box; require its avatar (verified absent on
    // signed-out pages) and treat the member link only as a fallback for the
    // name, never as the sign-in signal.
    final accountBox = sidebar.querySelector('div.box');
    final avatarImage =
        accountBox?.querySelector('img.avatar') ??
        sidebar.querySelector('img.avatar');
    if (avatarImage == null) return null;

    final username =
        cleanText(avatarImage.attributes['alt']) ??
        cleanText(sidebar.querySelector('a[href^="/member/"]')?.text);
    if (username == null || username.isEmpty) return null;

    final memberId = _memberIdFrom(
      avatarImage.attributes['data-uid'],
      sidebar.text,
    );

    return V2AccountInfo(
      user: V2User(
        username: username,
        id: memberId,
        avatarUrl: absoluteV2exUrl(avatarImage.attributes['src']),
      ),
      notifications: _notificationCount(sidebar),
      moneyGold: _money(document, 'G'),
      moneySilver: _money(document, 'S'),
      moneyBronze: _money(document, 'B'),
    );
  }

  /// `data-uid="94728"` first, else the `V2EX 第 94728 号会员` sentence the
  /// member page also uses.
  static int? _memberIdFrom(String? dataUid, String? sidebarText) {
    final direct = parseIntOrNull(dataUid);
    if (direct != null) return direct;
    final text = cleanText(sidebarText);
    if (text == null) return null;
    final match = RegExp(r'第\s*(\d+)\s*号').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// The unread-notification count.
  ///
  /// Live markup puts it in the sidebar's `div.cell.flex-one-row` row, whose
  /// first `<a>` text carries the number (`<a href="/notifications">3</a>`, or
  /// `3 条未读提醒`); the older/simpler shape links `/notifications` directly.
  /// `AuthSession.unreadCount` extracts the digits.
  static String? _notificationCount(Element sidebar) {
    final row = sidebar.querySelector('div.cell.flex-one-row');
    final anchor =
        row?.querySelector('a[href="/notifications"]') ??
        row?.querySelector('a') ??
        sidebar.querySelector('a[href="/notifications"]');
    return cleanText(anchor?.text);
  }

  /// The money icons live in `#money` as `<img alt="G">` preceded by the value.
  static String? _money(Document document, String currency) {
    final image = document.querySelector('div#money img[alt="$currency"]');
    if (image == null) return null;
    final previous = image.previousElementSibling;
    if (previous != null) return cleanText(previous.text);
    // Fall back to the text node immediately before the image.
    final parent = image.parent;
    if (parent == null) return null;
    final pieces = <String>[];
    for (final node in parent.nodes) {
      if (node == image) break;
      pieces.add(node.text ?? '');
    }
    final text = cleanText(pieces.join());
    return text;
  }
}

/// `/mission/daily` — the daily bonus page.
abstract final class DailyMissionParser {
  static V2DailyMission parse(String html) {
    final document = parseHtmlDocument(html);

    // The `已连续 N 天` sentence lives in a cell; the redeem button carries the
    // `once` token inside its inline `onclick`.
    String? continuous;
    for (final cell in document.querySelectorAll('div.cell')) {
      final text = cleanText(cell.text);
      if (text != null && text.contains('已连续')) {
        continuous = text;
        break;
      }
    }

    String? redeemUrl;
    for (final input in document.querySelectorAll('input[type="button"]')) {
      final onclick = input.attributes['onclick'];
      if (onclick == null) continue;
      final match =
          RegExp(r"'(/mission/daily/redeem\?once=[^']+)'")
              .firstMatch(onclick) ??
          RegExp(r'"(/mission/daily/redeem\?once=[^"]+)"')
              .firstMatch(onclick) ??
          RegExp(r'(/mission/daily/redeem\?once=\w+)').firstMatch(onclick);
      if (match != null) {
        redeemUrl = match.group(1);
        break;
      }
    }

    return V2DailyMission(
      continuousDaysLabel: continuous,
      redeemPath: redeemUrl,
      alreadyCheckedIn: redeemUrl == null,
    );
  }
}
