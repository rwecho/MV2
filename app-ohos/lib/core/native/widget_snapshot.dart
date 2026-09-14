import 'package:flutter/foundation.dart';

/// One row the Home Screen / Lock Screen widget may show.
@immutable
class Mv2WidgetItem {
  const Mv2WidgetItem({
    required this.actor,
    required this.text,
    this.topicId,
  });

  /// Who triggered the notification.
  final String actor;

  /// Quote (or the topic title when the notification carries no quote).
  final String text;

  /// Lets the widget deep-link back to `/topic/{id}`.
  final int? topicId;

  Map<String, Object?> toJson() => <String, Object?>{
    'actor': actor,
    'text': text,
    if (topicId != null) 'topicId': topicId,
  };
}

/// The document the MV2Widget extension renders.
///
/// Deliberately tiny and free of credentials: the extension only draws what the
/// app already fetched. It is JSON-encoded into the shared App Group container
/// by `MV2NativeBridge`, so a field rename here must be mirrored in
/// `ios/MV2Widget/WidgetSnapshot.swift`.
@immutable
class Mv2WidgetSnapshot {
  const Mv2WidgetSnapshot({
    required this.unreadCount,
    required this.updatedAt,
    this.signedIn = false,
    this.items = const <Mv2WidgetItem>[],
  });

  final int unreadCount;
  final DateTime updatedAt;

  /// Signed-out state renders a "登录后查看通知" placeholder instead of `0`.
  final bool signedIn;

  final List<Mv2WidgetItem> items;

  Map<String, Object?> toJson() => <String, Object?>{
    'unread': unreadCount,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'signedIn': signedIn,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };
}
