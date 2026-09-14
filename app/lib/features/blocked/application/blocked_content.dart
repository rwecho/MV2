import '../../../shared/models/models.dart';

/// Local content filter for 屏蔽用户.
///
/// Blocking is a **client-side preference** (`docs/13` Phase 5): V2EX's own
/// block endpoint is never called, so every surface that renders a username has
/// to drop blocked rows itself. Keeping the predicates in one place stops the
/// feed, node, search, reply and notification lists from drifting apart.
///
/// The raw models stay untouched — filtering happens in the application layer,
/// so a blocked user is still reachable by direct link and can be unblocked
/// without losing data.
abstract final class BlockedContent {
  /// Whether [username] is hidden. A `null` author is never blocked: an
  /// anonymous or unparsed author must not make content disappear silently.
  static bool hides(Set<String> blocked, String? username) =>
      username != null && blocked.contains(username);

  static List<V2Topic> topics(Set<String> blocked, List<V2Topic> topics) {
    if (blocked.isEmpty) return topics;
    return topics
        .where((topic) => !hides(blocked, topic.author.username))
        .toList(growable: false);
  }

  static List<V2Reply> replies(Set<String> blocked, List<V2Reply> replies) {
    if (blocked.isEmpty) return replies;
    return replies
        .where((reply) => !hides(blocked, reply.author.username))
        .toList(growable: false);
  }

  /// Drops empty day sections as well, so blocking one user cannot leave a
  /// "今天" header with nothing under it.
  static List<V2NotificationGroup> notificationGroups(
    Set<String> blocked,
    List<V2NotificationGroup> groups,
  ) {
    if (blocked.isEmpty) return groups;
    return <V2NotificationGroup>[
      for (final group in groups)
        if (group.items.any((item) => !hides(blocked, item.actor.username)))
          V2NotificationGroup(
            title: group.title,
            items: group.items
                .where((item) => !hides(blocked, item.actor.username))
                .toList(growable: false),
          ),
    ];
  }
}
