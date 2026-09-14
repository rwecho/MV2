import 'package:drift/drift.dart';

import '../../../core/storage/cache_database.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/node_visuals.dart';

/// Flat <-> model mapping for the local 稍后阅读 / 浏览历史 tables.
///
/// A `V2Topic` alone is not a complete history record (the feed model also
/// needs the node + author), so both directions go through every stored column
/// and rebuild the node/author from the shared [NodeVisuals] catalogue.

ReadLaterEntriesCompanion readLaterCompanionFromTopic(V2Topic topic) {
  return ReadLaterEntriesCompanion.insert(
    topicId: Value<int>(topic.id),
    title: topic.title,
    authorName: topic.author.username,
    authorAvatar: Value<String?>(topic.author.avatarUrl),
    nodeName: topic.node.name,
    nodeKey: topic.node.key,
    timeLabel: topic.createdAtLabel,
    replyCount: topic.replyCount,
    // Overwritten by the store on insert; callers never supply a timestamp.
    savedAt: DateTime.now(),
  );
}

HistoryEntriesCompanion historyCompanionFromTopic(V2Topic topic) {
  return HistoryEntriesCompanion.insert(
    topicId: Value<int>(topic.id),
    title: topic.title,
    authorName: topic.author.username,
    authorAvatar: Value<String?>(topic.author.avatarUrl),
    nodeName: topic.node.name,
    nodeKey: topic.node.key,
    timeLabel: topic.createdAtLabel,
    // Overwritten with `now` by `CacheDatabase.historyRecord`.
    viewedAt: DateTime.now(),
  );
}

V2Topic topicFromReadLater(ReadLaterEntry row) {
  return V2Topic(
    id: row.topicId,
    node: NodeVisuals.node(key: row.nodeKey, name: row.nodeName),
    title: row.title,
    author: V2User(username: row.authorName, avatarUrl: row.authorAvatar),
    createdAtLabel: row.timeLabel,
    replyCount: row.replyCount,
  );
}

V2Topic topicFromHistory(HistoryEntry row) {
  return V2Topic(
    id: row.topicId,
    node: NodeVisuals.node(key: row.nodeKey, name: row.nodeName),
    title: row.title,
    author: V2User(username: row.authorName, avatarUrl: row.authorAvatar),
    createdAtLabel: row.timeLabel,
    // The history table deliberately omits the reply count; the row tolerates
    // a zero count rather than blocking the record on feed-only data.
    replyCount: 0,
  );
}
