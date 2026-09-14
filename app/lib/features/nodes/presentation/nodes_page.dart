import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_refreshable.dart';
import '../../../ui/components/node_card.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../../ui/primitives/mv2_chips.dart';
import '../application/nodes_providers.dart';

/// Node exploration page (`designs/04-nodes-explore.png`).
class NodesPage extends ConsumerStatefulWidget {
  const NodesPage({super.key});

  @override
  ConsumerState<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends ConsumerState<NodesPage> {
  /// Navigates to a 最近访问 node; the slug comes straight from the local
  /// history snapshot, so no cross-reference with the hot list is needed.
  void _openRecentNode(RecentVisitedNode node) {
    context.push('/node/${node.key}?name=${Uri.encodeComponent(node.title)}');
  }

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(nodesProvider);
    final recentNodes = ref.watch(recentVisitedNodesProvider);
    ref.listen(nodesProvider, (p, n) => mv2ToastLoadError(context, p, n));

    return Mv2PageScaffold(
      header: Mv2PageHeader(
        title: '节点',
        subtitle: '发现感兴趣的内容社区',
        actions: <Widget>[
          const Mv2IconButton(
            icon: Icons.filter_list_rounded,
            filled: true,
            onPressed: null,
          ),
        ],
      ),
      child: Mv2Refreshable(
        onRefresh: () => ref.refresh(nodesProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            Mv2Spacing.pageNarrow,
            0,
            Mv2Spacing.pageNarrow,
            Mv2PageScaffold.bottomContentInset(context),
          ),
          children: <Widget>[
            _SearchField(onTap: () => context.push('/nodes/all')),
            const SizedBox(height: Mv2Spacing.x5),
            // 最近访问 comes purely from local history; the whole section
            // stays hidden until at least one node has been visited.
            if (recentNodes.value case final recentNodesValue?
                when recentNodesValue.isNotEmpty) ...<Widget>[
              _SectionHeader(
                title: '最近访问',
                actionLabel: '查看全部',
                onAction: () => context.push('/nodes/all'),
              ),
              const SizedBox(height: Mv2Spacing.x3),
              _RecentNodes(
                nodes: recentNodesValue,
                onSelect: _openRecentNode,
              ),
              const SizedBox(height: Mv2Spacing.x5),
            ],
            _SectionHeader(
              title: '热门节点',
              actionLabel: '查看更多',
              onAction: () => context.push('/nodes/all'),
            ),
            const SizedBox(height: Mv2Spacing.x3),
            nodes.when(
              skipLoadingOnReload: true,
              loading: () => const _NodesLoadingList(),
              error: (_, _) => Mv2StateView(
                kind: Mv2StateKind.error,
                actionLabel: '重试',
                onAction: () => ref.invalidate(nodesProvider),
              ),
              data: (hotNodes) => Column(
                children: <Widget>[
                  for (var i = 0; i < hotNodes.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: Mv2Spacing.x3),
                    NodeCard(
                      node: hotNodes[i],
                      onTap: () => context.push(
                        '/node/${hotNodes[i].key}?name=${Uri.encodeComponent(hotNodes[i].name)}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable search entry point; it hands off to the 全部节点 page, which owns
/// the actual filtering field.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Mv2Surface(
      borderRadius: Mv2Radius.allMd,
      padding: const EdgeInsets.symmetric(
        horizontal: Mv2Spacing.x4,
        vertical: Mv2Spacing.x3,
      ),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, size: 20, color: colors.textTertiary),
          const SizedBox(width: Mv2Spacing.x2),
          Text(
            '搜索节点',
            style: context.text.bodySmall.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Section title with a trailing text + chevron affordance.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: <Widget>[
        Text(
          title,
          style: context.text.sectionTitle.copyWith(color: colors.textPrimary),
        ),
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onAction,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                actionLabel,
                style: context.text.metadata.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Horizontally scrollable recent-node pills.
class _RecentNodes extends StatelessWidget {
  const _RecentNodes({required this.nodes, required this.onSelect});

  final List<RecentVisitedNode> nodes;
  final ValueChanged<RecentVisitedNode> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < nodes.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: Mv2Spacing.x2),
            Mv2Chip(label: nodes[i].title, onTap: () => onSelect(nodes[i])),
          ],
        ],
      ),
    );
  }
}

/// Loading placeholder matching [NodeCard] metrics.
class _NodesLoadingList extends StatelessWidget {
  const _NodesLoadingList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        _NodeCardSkeleton(),
        SizedBox(height: Mv2Spacing.x3),
        _NodeCardSkeleton(),
        SizedBox(height: Mv2Spacing.x3),
        _NodeCardSkeleton(),
        SizedBox(height: Mv2Spacing.x3),
        _NodeCardSkeleton(),
      ],
    );
  }
}

class _NodeCardSkeleton extends StatelessWidget {
  const _NodeCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Mv2Radius.allMd,
        border: Border.all(color: colors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Mv2SkeletonBox(width: 44, height: 44, radius: Mv2Radius.allSm),
          SizedBox(width: Mv2Spacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Mv2SkeletonBox(width: 120, height: 16),
                    Spacer(),
                    Mv2SkeletonBox(width: 56, height: 12),
                  ],
                ),
                SizedBox(height: Mv2Spacing.x3),
                Mv2SkeletonBox(width: double.infinity, height: 12),
                SizedBox(height: Mv2Spacing.x1),
                Mv2SkeletonBox(width: 200, height: 12),
                SizedBox(height: Mv2Spacing.x3),
                Row(
                  children: <Widget>[
                    Mv2SkeletonBox(width: 48, height: 20),
                    SizedBox(width: Mv2Spacing.x2),
                    Mv2SkeletonBox(width: 56, height: 20),
                    SizedBox(width: Mv2Spacing.x2),
                    Mv2SkeletonBox(width: 72, height: 20),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
