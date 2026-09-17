import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../../../shared/models/models.dart';

/// Opens a node's topic stream (`/node/:key`).
///
/// Single choke point mirroring `openTopic`: the slug goes into the path, the
/// display name into `?name=` (the slug is not the title — `programmer` vs
/// `程序员` — and without it the node page would fetch the whole directory just
/// to render its header). An empty title is left off so the page falls back to
/// the slug instead of showing a blank header.
///
/// [source] 是 `node_open` 的归因参数,调用入口见 `Mv2Events.nodeOpen`。
void openNode(BuildContext context, V2Node node, {required String source}) {
  if (node.key.isEmpty) return;
  Mv2Analytics.logNodeOpen(nodeKey: node.key, source: source);
  final name = node.name.isEmpty
      ? ''
      : '?name=${Uri.encodeComponent(node.name)}';
  context.push('/node/${node.key}$name');
}
