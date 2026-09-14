import 'package:flutter/widgets.dart';

/// Domain models used by the MV2 presentation layer.
///
/// These are intentionally payload-agnostic: the data layer (V2EX API + HTML
/// parser) maps into them, and the UI never sees raw JSON/HTML
/// (`docs/03-technical-architecture.md` §3, §6).
///
/// Until the Dio/Drift layer lands they are fed by `shared/mock/`
/// fixtures that mirror `designs/*.png` one-to-one.

@immutable
class V2Node {
  const V2Node({
    required this.key,
    required this.name,
    required this.icon,
    this.topicCount,
    this.description,
    this.tags = const <String>[],
    this.iconStyle = NodeIconStyle.solid,
    this.nodeId,
  });

  /// Stable slug, e.g. `programmer`.
  final String key;

  /// Display name, e.g. `程序员`.
  final String name;

  /// Numeric V2EX node id, e.g. `864` for `promotions`. sov2ex search hits
  /// carry this number instead of the slug, so it is the key into the
  /// `/api/nodes/all.json` directory. `null` when the payload only exposed a
  /// slug (feeds, `/api/nodes/s2.json`).
  final int? nodeId;

  /// Glyph shown inside the node tile.
  final IconData icon;

  final int? topicCount;
  final String? description;
  final List<String> tags;
  final NodeIconStyle iconStyle;
}

/// Node tile rendering style seen in `designs/04-nodes-explore.png`:
/// most nodes render as a saturated tile with a white glyph, while a few
/// (e.g. `AI`) render as a soft tint with a colored glyph.
enum NodeIconStyle { solid, soft }

@immutable
class V2User {
  const V2User({required this.username, this.avatarUrl, this.id, this.tagline});

  final String username;
  final String? avatarUrl;

  /// V2EX member number, e.g. `94728` (rendered as `V2EX #94728`).
  final int? id;
  final String? tagline;
}

@immutable
class V2Topic {
  const V2Topic({
    required this.id,
    required this.node,
    required this.title,
    required this.author,
    required this.createdAtLabel,
    required this.replyCount,
    this.excerpt,
    this.isRead = false,
    this.isPinned = false,
    this.viewCountLabel,
    this.body,
    this.linkPreview,
    this.url,
  });

  final int id;
  final V2Node node;
  final String title;

  /// On the feed pages V2EX renders the **last replier**, not the topic author
  /// (`docs/12` §2.2). The detail page carries the real author.
  final V2User author;

  /// Pre-formatted relative time (`3 小时前`). Formatting is a data-layer
  /// concern so the UI stays locale-agnostic.
  final String createdAtLabel;

  final int replyCount;
  final String? excerpt;
  final bool isRead;

  /// Feed pages mark pinned topics with the literal `置顶`.
  final bool isPinned;

  final String? viewCountLabel;

  /// Detail-only rich content.
  final List<String>? body;
  final V2LinkPreview? linkPreview;

  /// Absolute URL on v2ex.com.
  final String? url;

  V2Topic copyWith({
    int? id,
    V2Node? node,
    String? title,
    V2User? author,
    String? createdAtLabel,
    int? replyCount,
    String? excerpt,
    bool? isRead,
    bool? isPinned,
    String? viewCountLabel,
    List<String>? body,
    V2LinkPreview? linkPreview,
    String? url,
  }) {
    return V2Topic(
      id: id ?? this.id,
      node: node ?? this.node,
      title: title ?? this.title,
      author: author ?? this.author,
      createdAtLabel: createdAtLabel ?? this.createdAtLabel,
      replyCount: replyCount ?? this.replyCount,
      excerpt: excerpt ?? this.excerpt,
      isRead: isRead ?? this.isRead,
      isPinned: isPinned ?? this.isPinned,
      viewCountLabel: viewCountLabel ?? this.viewCountLabel,
      body: body ?? this.body,
      linkPreview: linkPreview ?? this.linkPreview,
      url: url ?? this.url,
    );
  }
}

/// One entry of V2EX's VXNA aggregator (`/xna`).
///
/// Unlike [V2Topic] these are **external** articles syndicated from the
/// sources V2EX follows: the title links off-site, there is no reply count and
/// no on-site topic id. The card therefore renders a source badge instead of a
/// node badge and opens the URL in the browser.
@immutable
class V2XnaEntry {
  const V2XnaEntry({
    required this.title,
    required this.url,
    required this.sourceName,
    this.sourceUrl,
    this.author,
    this.timeLabel,
  });

  final String title;

  /// Absolute external article URL (`https://blog.example.com/post`).
  final String url;

  /// Source site label, e.g. `素生` (the `a.node` next to the time).
  final String sourceName;
  final String? sourceUrl;

  /// V2EX member who syndicates this source, when the page exposes it.
  final V2User? author;

  /// Pre-formatted relative time (`4 小时 0 分钟前`).
  final String? timeLabel;
}

@immutable
class V2LinkPreview {
  const V2LinkPreview({
    required this.title,
    required this.description,
    required this.url,
  });

  final String title;
  final String description;
  final String url;
}

@immutable
class V2Reply {
  const V2Reply({
    required this.floor,
    required this.author,
    required this.content,
    required this.createdAtLabel,
    this.id,
    this.contentHtml,
    this.likes = 0,
    this.thanked = false,
    this.isOwner = false,
    this.badges = const <String>[],
  });

  /// V2EX reply id (the `r_<id>` cell's numeric suffix); needed for
  /// thank/ignore write actions.
  final String? id;

  final int floor;
  final V2User author;

  /// Plain-text projection of [contentHtml], used for quotes and previews.
  final String content;

  /// Raw V2EX HTML — rendered by the MV2 rich-text renderer.
  final String? contentHtml;

  final String createdAtLabel;
  final int likes;
  final bool thanked;

  /// True when the replier is the topic author (楼主).
  final bool isOwner;

  /// Site-rendered badges, e.g. `OP` (楼主) or `PRO`. V2EX emits these as
  /// `<div class="badge op">OP</div>` inside `div.badges`.
  final List<String> badges;
}

enum NotificationKind { reply, mention, like, favorite }

@immutable
class V2Notification {
  const V2Notification({
    required this.id,
    required this.kind,
    required this.actor,
    required this.timeLabel,
    required this.quote,
    required this.sourceTitle,
    this.topicId,
    this.topicUrl,
    this.isUnread = false,
  });

  final String id;
  final NotificationKind kind;
  final V2User actor;
  final String timeLabel;

  /// Quoted snippet of the reply/comment.
  final String quote;

  /// Title of the topic the notification points at.
  final String sourceTitle;

  /// Numeric topic id parsed from the `a.topic-link` href (`/t/123#reply4`).
  final int? topicId;

  /// Absolute `a.topic-link` href.
  final String? topicUrl;

  final bool isUnread;
}

@immutable
class V2NotificationGroup {
  const V2NotificationGroup({required this.title, required this.items});

  final String title;
  final List<V2Notification> items;
}

@immutable
class V2Profile {
  const V2Profile({
    required this.user,
    required this.topicCount,
    required this.replyCount,
    required this.favoriteCount,
    this.recentTopics = const <V2Topic>[],
    this.joinedAtLabel,
  });

  final V2User user;

  /// `2010-04-25` — scraped from `V2EX 第 N 号会员，加入于 …`. `null` when the
  /// page does not expose it.
  final String? joinedAtLabel;

  /// `null` when V2EX does not expose the counter (the public member page only
  /// shows `V2EX 第 N 号会员`), so the UI can hide the stat strip instead of
  /// claiming `0`.
  final int? topicCount;
  final int? replyCount;
  final int? favoriteCount;

  /// The member's most recent topics as exposed by `/member/{username}`
  /// (empty when the page does not render the list).
  final List<V2Topic> recentTopics;
}
