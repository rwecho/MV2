import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/provider_retry.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/topic_detail.dart';

/// Hot node list for the 节点探索 page (`/api/nodes/list.json`).
final nodesProvider = FutureProvider<List<V2Node>>((ref) {
  return ref.watch(v2exApiProvider).nodes();
}, retry: mv2Retry);

/// Node topic stream (`/go/{node}`). Not designed yet — see `docs/11` D5.
final nodePageProvider = FutureProvider.family<V2NodePage, NodePageArgs>((
  ref,
  args,
) {
  return ref.watch(v2exApiProvider).nodePage(args.nodeName, page: args.page);
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
