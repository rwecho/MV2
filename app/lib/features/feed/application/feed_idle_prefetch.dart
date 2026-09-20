import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/cache_ttl.dart';
import '../../../core/data/home_tab.dart';
import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/mv2_http_client.dart';

/// 闲时预取：当前 tab 的 feed 就绪后，把相邻 tab 的列表提前拉进磁盘缓存。
///
/// 「闲时」不是靠空闲检测，而是靠 pacer 的优先级队列实现：预取以
/// [PacePriority.backgroundRead] 入队，用户一有主动请求就被插队；任意时刻
/// 仍然只有一个请求在飞，V2EX 反 flood 的节奏保证不变。已在新鲜窗口内的
/// tab 直接跳过，不烧 v1 API 配额。预取失败静默——用户滑过去时 provider
/// 自己会再请求。
Future<void> prefetchNeighborFeeds(Ref ref, HomeTab tab) async {
  final api = ref.read(v2exApiProvider);
  for (final neighbor in _neighborsOf(tab)) {
    if (!ref.mounted) return;
    try {
      final cached = await api.feedCached(neighbor, maxAge: CacheTtl.feedFresh);
      if (cached != null) continue;
      await api.feed(neighbor, priority: PacePriority.backgroundRead);
    } on Failure {
      // A prefetch must never surface as an error; give up on this round.
      return;
    }
  }
}

/// PageView 顺序上的左右邻居，跳过 VXNA（聚合页走 [xnaFeedProvider]，不在
/// 话题列表缓存体系内）。
List<HomeTab> _neighborsOf(HomeTab tab) {
  final values = HomeTab.values;
  final index = tab.index;
  return <HomeTab>[
    if (index > 0) values[index - 1],
    if (index + 1 < values.length) values[index + 1],
  ].where((candidate) => !candidate.isAggregator).toList(growable: false);
}
