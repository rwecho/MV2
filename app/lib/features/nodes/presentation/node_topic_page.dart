import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_refreshable.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/components/topic_item.dart';
import '../../topic/application/open_topic.dart';
import '../application/nodes_providers.dart';

/// Topic stream for a single node (`/go/{node}`).
///
/// A secondary list page: back affordance + node title, then the same
/// [TopicItem] metrics as the home feed.
class NodeTopicPage extends ConsumerWidget {
  const NodeTopicPage({super.key, required this.nodeName, this.displayName});

  /// Node slug from the route (`/node/:key`).
  final String nodeName;

  /// Human-readable node title (`程序员`); falls back to the slug.
  final String? displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = NodePageArgs(nodeName);
    final page = ref.watch(nodePageProvider(args));
    final bottomInset = Mv2PageScaffold.bottomContentInset(context);
    Future<void> refresh() => ref.refresh(nodePageProvider(args).future);
    ref.listen(
      nodePageProvider(args),
      (p, n) => mv2ToastLoadError(context, p, n),
    );

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(
        title: displayName ?? nodeName,
        onBack: () => context.pop(),
      ),
      child: page.when(
        skipLoadingOnReload: true,
        loading: () => Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: const TopicListSkeleton(),
        ),
        error: (_, _) => Mv2RefreshableFill(
          onRefresh: refresh,
          child: Mv2StateView(
            kind: Mv2StateKind.error,
            actionLabel: '重试',
            onAction: () => ref.invalidate(nodePageProvider(args)),
          ),
        ),
        data: (data) {
          if (data.topics.isEmpty) {
            return Mv2RefreshableFill(
              onRefresh: refresh,
              child: const Mv2StateView(kind: Mv2StateKind.empty),
            );
          }
          return Mv2Refreshable(
            onRefresh: refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                Mv2Spacing.pageNarrow,
                0,
                Mv2Spacing.pageNarrow,
                bottomInset,
              ),
              itemCount: data.topics.length,
              separatorBuilder: (_, _) => const SizedBox(height: Mv2Spacing.x3),
              itemBuilder: (context, index) {
                final topic = data.topics[index];
                return TopicItem(
                  topic: topic,
                  onTap: () => openTopic(context, topic.id),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
