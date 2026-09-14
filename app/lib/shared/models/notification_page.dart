import 'package:flutter/foundation.dart';

import 'models.dart';
import 'topic_detail.dart';

/// One page of `/notifications`.
///
/// [groups] are the day sections the UI renders (今天 / 昨天 / 更早); a
/// signed-out request produces an empty page with [isSignedOut] set so the
/// page can show the sign-in call to action instead of an empty list.
///
/// [feedUrl] is the account's private notification Atom feed (`input.sll`). The
/// push worker polls it every 15 minutes, so registration cannot happen until
/// the user has visited this page at least once (`docs/12` §8).
@immutable
class NotificationPage {
  const NotificationPage({
    this.groups = const <V2NotificationGroup>[],
    this.pagination = const V2Pagination(),
    this.isSignedOut = false,
    this.feedUrl,
  });

  /// Signed-out shell: `/notifications` answers `302 → /signin`.
  const NotificationPage.signedOut()
    : groups = const <V2NotificationGroup>[],
      pagination = const V2Pagination(),
      isSignedOut = true,
      feedUrl = null;

  final List<V2NotificationGroup> groups;
  final V2Pagination pagination;
  final bool isSignedOut;

  /// `https://www.v2ex.com/feed/notifications.xml?once=…`, or `null` when the
  /// page did not carry the input.
  final String? feedUrl;

  /// Flattened items in page order (handy for badges / counts).
  List<V2Notification> get items => <V2Notification>[
    for (final group in groups) ...group.items,
  ];

  bool get isEmpty => items.isEmpty;

  NotificationPage copyWith({
    List<V2NotificationGroup>? groups,
    V2Pagination? pagination,
    bool? isSignedOut,
    String? feedUrl,
  }) {
    return NotificationPage(
      groups: groups ?? this.groups,
      pagination: pagination ?? this.pagination,
      isSignedOut: isSignedOut ?? this.isSignedOut,
      feedUrl: feedUrl ?? this.feedUrl,
    );
  }
}
