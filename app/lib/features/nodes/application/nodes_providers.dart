import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/provider_retry.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/topic_detail.dart';
import '../../blocked/application/blocked_content.dart';
import '../../blocked/application/blocked_users_controller.dart';

/// Hot node list for the 节点探索 page (`/api/nodes/list.json`).
final nodesProvider = FutureProvider<List<V2Node>>((ref) {
  return ref.watch(v2exApiProvider).nodes();
}, retry: mv2Retry);

/// One 最近访问 chip, derived from the local browsing history.
class RecentVisitedNode {
  const RecentVisitedNode({required this.key, required this.title});

  /// Node slug used in the `/node/{key}` route.
  final String key;

  /// Display title shown on the chip.
  final String title;
}

/// 最近访问 nodes: distinct node visits from the local history, newest first.
///
/// Purely local — there is no seeded sample list. Empty until the user has
/// opened at least one topic, in which case the section simply hides.
final recentVisitedNodesProvider = FutureProvider<List<RecentVisitedNode>>((
  ref,
) async {
  final rows = await ref.watch(cacheDatabaseProvider).historyAll();
  final seen = <String>{};
  final recent = <RecentVisitedNode>[];
  for (final row in rows) {
    if (row.nodeKey.isEmpty || !seen.add(row.nodeKey)) continue;
    recent.add(RecentVisitedNode(key: row.nodeKey, title: row.nodeName));
    if (recent.length >= 8) break;
  }
  return recent;
});

/// Node topic stream (`/go/{node}`). Not designed yet — see `docs/11` D5.
final nodePageProvider = FutureProvider.family<V2NodePage, NodePageArgs>((
  ref,
  args,
) async {
  final page = await ref
      .watch(v2exApiProvider)
      .nodePage(args.nodeName, page: args.page);
  final blocked = ref.watch(blockedUsersProvider);
  if (blocked.isEmpty) return page;
  return V2NodePage(
    nodeName: page.nodeName,
    title: page.title,
    topics: BlockedContent.topics(blocked, page.topics),
    pagination: page.pagination,
  );
}, retry: mv2Retry);

class NodePageArgs {
  const NodePageArgs(this.nodeName, {this.page = 1});

  final String nodeName;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is NodePageArgs && other.nodeName == nodeName && other.page == page;

  @override
  int get hashCode => Object.hash(nodeName, page);
}
