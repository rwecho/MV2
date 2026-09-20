import '../../shared/models/models.dart';
import '../../shared/models/node_visuals.dart';
import 'html_dom.dart';

/// V2EX v1 JSON API (`/api/topics/latest.json`, `/api/topics/hot.json`,
/// `/api/members/show.json`) → shared models.
///
/// The official JSON endpoints are the fast path — light payloads, no DOM
/// parsing — while the HTML scrapes stay as the fallback the callers drop to
/// whenever the JSON request or this parser fails. The v1 list payload is
/// stable and self-describing (verified live 2026-09), so a structural change
/// surfaces as a fallback silently rather than a broken page loudly.
abstract final class V1JsonParser {
  /// `latest.json` / `hot.json` → feed rows.
  ///
  /// Feed pages render the **last replier** (`docs/12` §2.2); the JSON list
  /// carries `last_reply_by` as a bare username without an avatar, so when
  /// present it wins and the avatar falls back to the gradient tile. Topics
  /// with no replies keep the author (and their real avatar).
  static List<V2Topic> parseTopicList(Object? json) {
    if (json is! List) return const <V2Topic>[];
    final topics = <V2Topic>[];
    for (final item in json) {
      if (item is! Map) continue;
      final topic = _topic(item);
      if (topic != null) topics.add(topic);
    }
    return topics;
  }

  static V2Topic? _topic(Map<Object?, Object?> item) {
    final id = (item['id'] as num?)?.toInt();
    final title = cleanText(item['title']?.toString());
    if (id == null || title == null) return null;

    final member = _map(item['member']);
    final node = _map(item['node']);
    final lastReplyBy = cleanText(item['last_reply_by']?.toString());

    final V2User author;
    if (lastReplyBy != null) {
      author = V2User(username: lastReplyBy);
    } else {
      author = _user(member) ?? const V2User(username: '匿名');
    }

    return V2Topic(
      id: id,
      node: NodeVisuals.node(
        key: cleanText(node?['name']?.toString()) ?? '',
        name: cleanText(node?['title']?.toString()) ?? '',
        nodeId: (node?['id'] as num?)?.toInt(),
      ),
      title: title,
      author: author,
      createdAtLabel: relativeTime(
        (item['last_touched'] ?? item['created']) as num?,
      ),
      replyCount: (item['replies'] as num?)?.toInt() ?? 0,
    );
  }

  /// `members/show.json` → [V2Profile]. The v1 payload carries no topic /
  /// reply / favorite counters — they stay `null` so the member page hides
  /// its stat strip instead of claiming `0`. `null` when unusable (unknown
  /// member), which sends the caller to the HTML fallback.
  static V2Profile? parseProfile(Object? json) {
    final member = _map(json);
    final user = _user(member);
    if (user == null) return null;

    final created = (member?['created'] as num?)?.toInt();
    return V2Profile(
      user: user,
      topicCount: null,
      replyCount: null,
      favoriteCount: null,
      joinedAtLabel: created == null ? null : _dateLabel(created),
    );
  }

  static V2User? _user(Map<Object?, Object?>? member) {
    final username = cleanText(member?['username']?.toString());
    if (username == null) return null;
    final avatar =
        (member?['avatar_large'] ??
                member?['avatar_normal'] ??
                member?['avatar_mini'])
            ?.toString();
    return V2User(
      username: username,
      avatarUrl: absoluteV2exUrl(avatar),
      id: (member?['id'] as num?)?.toInt(),
      tagline: cleanText(member?['tagline']?.toString()),
    );
  }

  static Map<Object?, Object?>? _map(Object? raw) =>
      raw is Map ? raw.cast<Object?, Object?>() : null;

  /// Unix seconds → `刚刚 / N 分钟前 / N 小时前 / N 天前 / YYYY-MM-DD`.
  ///
  /// Same label rules as the site (and [SearchParser]'s ISO variant), because
  /// the JSON payloads carry timestamps where the HTML ships pre-formatted
  /// labels.
  static String relativeTime(num? unixSeconds) {
    if (unixSeconds == null) return '';
    final created = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds.toInt() * 1000,
    );
    final elapsed = DateTime.now().difference(created);
    if (elapsed.isNegative || elapsed.inMinutes < 1) return '刚刚';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
    if (elapsed.inDays < 1) return '${elapsed.inHours} 小时前';
    if (elapsed.inDays < 30) return '${elapsed.inDays} 天前';
    return _dateLabel(unixSeconds.toInt());
  }

  static String _dateLabel(int unixSeconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
