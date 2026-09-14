import 'package:html/dom.dart';

import '../../shared/models/models.dart';
import '../../shared/models/notification_page.dart';
import 'html_dom.dart';
import 'pagination_parser.dart';

/// Parses `/notifications` into a [NotificationPage].
///
/// Verified against the documented live shape (`docs/12` §2.2): notification
/// items are `div[id^="n_"]` under `div#Wrapper`; the actor sits in a
/// `td strong`, the avatar in `td a img`, the topic title in an
/// `a.topic-link`, the relative time in `span.snow` and the quoted snippet in
/// `div.payload`.
///
/// ## Grouping
///
/// Items are grouped into 今天 / 昨天 / 更早. The page's own day separators are
/// honoured **when present** (an innermost `div` whose whole text is one of the
/// day labels); because the signed-in page cannot be captured without login,
/// the robust fallback groups by the `span.snow` text instead. Both paths are
/// covered by `test/notification_parser_test.dart`.
///
/// ## Signed out
///
/// `/notifications` answers `302 → /signin` for anonymous sessions and the HTTP
/// client does not follow redirects, so the API layer maps that redirect to
/// [NotificationPage.signedOut] before the parser is involved. If a signed-out
/// shell, an empty body or an unknown page does reach the parser it must not
/// throw: it returns an empty page with `current == maximum == 1`.
abstract final class NotificationParser {
  /// Canonical group order (`designs/06-notifications.png` shows 今天/昨天).
  static const List<String> groupOrder = <String>['今天', '昨天', '更早'];

  /// Day literals a separator cell may contain.
  static const Set<String> _dayLabels = <String>{'今天', '昨天', '更早'};

  static NotificationPage parse(String html) {
    final document = parseHtmlDocument(html);
    final wrapper = document.querySelector('div#Wrapper') ?? document.body;
    final pagination = parsePagination(wrapper ?? document.documentElement!);
    final feedUrl = _feedUrl(document);

    final items = document.querySelectorAll('div[id^="n_"]');
    if (items.isEmpty) {
      return NotificationPage(
        groups: const <V2NotificationGroup>[],
        pagination: pagination,
        isSignedOut: _looksSignedOut(document, wrapper),
        feedUrl: feedUrl,
      );
    }

    final buckets = _bucketize(wrapper, items);
    final groups = <V2NotificationGroup>[
      for (final title in groupOrder)
        if (buckets[title]?.isNotEmpty ?? false)
          V2NotificationGroup(title: title, items: buckets[title]!),
    ];

    return NotificationPage(
      groups: groups,
      pagination: pagination,
      feedUrl: feedUrl,
    );
  }

  /// The account's notification Atom feed, exposed as a hidden `input.sll`
  /// right of the page title. It carries a per-account `once` token, so the
  /// push worker — not the client — is the one that polls it; the client only
  /// forwards it once per device registration.
  static String? _feedUrl(Document document) {
    final value = document
        .querySelector('input.sll')
        ?.attributes['value']
        ?.trim();
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || !uri.host.endsWith('v2ex.com')) {
      return null;
    }
    return value;
  }

  /// Groups notifications by day title, honouring explicit separators first.
  static Map<String, List<V2Notification>> _bucketize(
    Element? wrapper,
    List<Element> items,
  ) {
    final buckets = <String, List<V2Notification>>{};

    if (wrapper == null) {
      for (final item in items) {
        final parsed = _parseItem(item);
        if (parsed != null) {
          buckets
              .putIfAbsent(
                groupTitleFor(parsed.timeLabel),
                () => <V2Notification>[],
              )
              .add(parsed);
        }
      }
      return buckets;
    }

    // Walk the wrapper in document order so day separators and notification
    // items interleave exactly as they appear on the page.
    final markers = <Object>[];
    for (final element in wrapper.querySelectorAll('*')) {
      if ((element.attributes['id'] ?? '').startsWith('n_')) {
        markers.add(element);
        continue;
      }
      final label = _separatorLabel(element);
      if (label != null) markers.add(label);
    }

    final usesSeparators = markers.any((marker) => marker is String);
    String? current;
    for (final marker in markers) {
      if (marker is String) {
        current = marker;
        continue;
      }
      final parsed = _parseItem(marker as Element);
      if (parsed == null) continue;
      final title = usesSeparators && current != null
          ? current
          : groupTitleFor(parsed.timeLabel);
      buckets.putIfAbsent(title, () => <V2Notification>[]).add(parsed);
    }
    return buckets;
  }

  /// Day title for a section separator, or `null` when [element] is not one.
  ///
  /// Only the innermost element carrying the label counts, so a wrapper that
  /// merely contains the separator is not counted twice.
  static String? _separatorLabel(Element element) {
    if (element.localName != 'div') return null;
    if (element.querySelector('div[id^="n_"]') != null) return null;
    final text = cleanText(element.text);
    if (text == null || !_dayLabels.contains(text)) return null;
    final duplicated = element
        .querySelectorAll('div')
        .any((child) => cleanText(child.text) == text);
    return duplicated ? null : text;
  }

  static V2Notification? _parseItem(Element item) {
    final rawId = item.attributes['id'];
    if (rawId == null || rawId.isEmpty) return null;
    final id = rawId.startsWith('n_') ? rawId.substring(2) : rawId;

    final actor =
        item.querySelector('td strong a') ?? item.querySelector('td strong');
    final actorName = cleanText(actor?.text) ?? '匿名';
    final avatar =
        item.attrOf('td a img', 'src') ?? item.attrOf('img.avatar', 'src');

    final topicAnchor = item.querySelector('a.topic-link');
    final payload = item.querySelector('div.payload');
    final href = topicAnchor?.attributes['href'];

    return V2Notification(
      id: id,
      kind: _kindFor(_actionText(item)),
      actor: V2User(username: actorName, avatarUrl: absoluteV2exUrl(avatar)),
      timeLabel: cleanText(item.querySelector('span.snow')?.text) ?? '',
      quote: cleanText(payload?.text) ?? '',
      sourceTitle: cleanText(topicAnchor?.text) ?? '',
      topicId: parseIdFromUrl(href),
      topicUrl: absoluteV2exUrl(href),
      // The unread marker is unverifiable without a signed-in capture; accept
      // the obvious class hooks and default to read.
      isUnread:
          item.classes.any((c) => c.toLowerCase().contains('unread')) ||
          item.querySelector('.unread') != null,
    );
  }

  /// Item text without the quoted payload, so `@` inside a quote cannot turn a
  /// reply notification into a mention.
  static String _actionText(Element item) {
    final parts = <String>[];
    void walk(Node node) {
      for (final child in node.nodes) {
        if (child is Element) {
          if (child.classes.contains('payload')) continue;
          walk(child);
        } else {
          parts.add(child.text ?? '');
        }
      }
    }

    walk(item);
    return cleanText(parts.join(' ')) ?? '';
  }

  /// Maps V2EX's action phrasing to [NotificationKind].
  static NotificationKind _kindFor(String text) {
    if (text.contains('收藏')) return NotificationKind.favorite;
    if (text.contains('感谢') || text.contains('赞')) return NotificationKind.like;
    if (text.contains('提到') || text.contains('@')) {
      return NotificationKind.mention;
    }
    return NotificationKind.reply;
  }

  /// Groups a `span.snow` label (今天/昨天/更早) without a day separator.
  ///
  /// V2EX renders relative labels (`3 小时前`, `1 天前`) and absolute dates
  /// (`8 月 31 日`).
  static String groupTitleFor(String timeLabel) {
    if (timeLabel.contains('今天')) return '今天';
    if (timeLabel.contains('昨天')) return '昨天';
    if (RegExp(r'\d+\s*(秒|分钟|小时)前').hasMatch(timeLabel)) return '今天';
    if (RegExp(r'^1\s*天前').hasMatch(timeLabel)) return '昨天';
    return '更早';
  }

  /// A page is treated as signed out when it carries no notification items and
  /// either renders the sign-in form or is an empty document shell (the shape
  /// an unfollowed `/signin` redirect can leave behind).
  static bool _looksSignedOut(Document document, Element? wrapper) {
    if (wrapper == null) return true;
    if (document.querySelector('form[action*="/signin"]') != null) return true;
    return wrapper.querySelector('*') == null;
  }
}
