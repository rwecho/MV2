import 'package:flutter/foundation.dart';

import 'models.dart';

/// Topic detail payload (`/t/{id}`), richer than the list-item [V2Topic].
@immutable
class V2TopicDetail {
  const V2TopicDetail({
    required this.topic,
    this.contentHtml,
    this.supplements = const <V2Supplement>[],
    this.tags = const <String>[],
    this.statsLabel,
    this.replyStatsLabel,
    this.favorited = false,
    this.thanked = false,
    this.ignored = false,
    this.once,
    this.pagination = const V2Pagination(),
    this.replies = const <V2Reply>[],
  });

  /// List-level fields (title, node, author, reply count…) reused as-is.
  final V2Topic topic;

  final String? contentHtml;
  final List<V2Supplement> supplements;
  final List<String> tags;

  /// e.g. `2.3k 次点击`.
  final String? statsLabel;

  /// e.g. `54 条回复`.
  final String? replyStatsLabel;

  final bool favorited;
  final bool thanked;
  final bool ignored;

  /// Session CSRF token scraped from the page; required by every write action
  /// on this topic (`docs/12` §4).
  final String? once;

  final V2Pagination pagination;
  final List<V2Reply> replies;

  bool get canReply => once != null && once!.isNotEmpty;

  V2TopicDetail copyWith({
    V2Topic? topic,
    String? contentHtml,
    List<V2Supplement>? supplements,
    List<String>? tags,
    String? statsLabel,
    String? replyStatsLabel,
    bool? favorited,
    bool? thanked,
    bool? ignored,
    String? once,
    V2Pagination? pagination,
    List<V2Reply>? replies,
  }) {
    return V2TopicDetail(
      topic: topic ?? this.topic,
      contentHtml: contentHtml ?? this.contentHtml,
      supplements: supplements ?? this.supplements,
      tags: tags ?? this.tags,
      statsLabel: statsLabel ?? this.statsLabel,
      replyStatsLabel: replyStatsLabel ?? this.replyStatsLabel,
      favorited: favorited ?? this.favorited,
      thanked: thanked ?? this.thanked,
      ignored: ignored ?? this.ignored,
      once: once ?? this.once,
      pagination: pagination ?? this.pagination,
      replies: replies ?? this.replies,
    );
  }
}

/// `附言` block attached to a topic.
@immutable
class V2Supplement {
  const V2Supplement({this.createdAtLabel, this.contentHtml});

  final String? createdAtLabel;
  final String? contentHtml;
}

/// 1-based page window.
@immutable
class V2Pagination {
  const V2Pagination({this.current = 1, this.maximum = 1});

  final int current;
  final int maximum;

  bool get hasPrevious => current > 1;
  bool get hasMore => current < maximum;

  V2Pagination copyWith({int? current, int? maximum}) => V2Pagination(
    current: current ?? this.current,
    maximum: maximum ?? this.maximum,
  );
}

/// Node topic list page (`/go/{node}`).
@immutable
class V2NodePage {
  const V2NodePage({
    required this.nodeName,
    this.title,
    this.topics = const <V2Topic>[],
    this.pagination = const V2Pagination(),
  });

  final String nodeName;
  final String? title;
  final List<V2Topic> topics;
  final V2Pagination pagination;
}
