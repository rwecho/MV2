import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/format/mv2_format.dart';
import '../../../shared/models/models.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_refreshable.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/primitives/mv2_chips.dart';
import '../../auth/application/auth_controller.dart';
import '../application/my_providers.dart';

/// 我的节点 — the signed-in member's favourite nodes (`/my/nodes`).
///
/// One icon row per node (tile + name + topic count), matching 设置's icon-row
/// rhythm; tapping opens the node's topic stream.
class MyNodesPage extends ConsumerWidget {
  const MyNodesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final nodes = ref.watch(favoriteNodesProvider);
    final bottomInset = Mv2PageScaffold.bottomContentInset(context);
    ref.listen(
      favoriteNodesProvider,
      (p, n) => mv2ToastLoadError(context, p, n),
    );

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(title: '我的节点', onBack: () => context.pop()),
      child: !signedIn
          ? Mv2StateView(
              kind: Mv2StateKind.empty,
              title: '登录后查看',
              description: '登录 V2EX 后即可同步收藏的节点。',
              actionLabel: '去登录',
              onAction: () => context.push('/login'),
            )
          : nodes.when(
              skipLoadingOnReload: true,
              loading: () => Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: const _NodeListSkeleton(),
              ),
              error: (_, _) => Mv2RefreshableFill(
                onRefresh: () => ref.refresh(favoriteNodesProvider.future),
                child: Mv2StateView(
                  kind: Mv2StateKind.error,
                  actionLabel: '重试',
                  onAction: () => ref.invalidate(favoriteNodesProvider),
                ),
              ),
              data: (List<V2Node> favorites) {
                if (favorites.isEmpty) {
                  return Mv2RefreshableFill(
                    onRefresh: () => ref.refresh(favoriteNodesProvider.future),
                    child: const Mv2StateView(
                      kind: Mv2StateKind.empty,
                      title: '还没有收藏的节点',
                      description: '在节点页收藏，就会出现在这里。',
                    ),
                  );
                }
                return Mv2Refreshable(
                  onRefresh: () => ref.refresh(favoriteNodesProvider.future),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      Mv2Spacing.pageNarrow,
                      0,
                      Mv2Spacing.pageNarrow,
                      bottomInset,
                    ),
                    itemCount: favorites.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Mv2Spacing.x3),
                    itemBuilder: (context, index) {
                      final node = favorites[index];
                      return _NodeRow(
                        node: node,
                        onTap: () => context.push(
                          '/node/${node.key}?name=${Uri.encodeComponent(node.name)}',
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

/// One favourite node: tile, display name, topic count, chevron.
class _NodeRow extends StatelessWidget {
  const _NodeRow({required this.node, this.onTap});

  final V2Node node;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Mv2Surface(
      borderRadius: Mv2Radius.allMd,
      shadowed: false,
      onTap: onTap,
      padding: const EdgeInsets.all(Mv2Spacing.x3),
      child: Row(
        children: <Widget>[
          Mv2NodeTile(node: node, size: 44),
          const SizedBox(width: Mv2Spacing.x3),
          Expanded(
            child: Text(
              node.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.itemTitle.copyWith(color: colors.textPrimary),
            ),
          ),
          if (node.topicCount != null) ...<Widget>[
            Text(
              '${Mv2Format.compactCount(node.topicCount!)} 主题',
              style: context.text.metadata.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(width: Mv2Spacing.x1),
          ],
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colors.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder matching [_NodeRow] metrics.
class _NodeListSkeleton extends StatelessWidget {
  const _NodeListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: Mv2Spacing.pageNarrow),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: Mv2Spacing.x3),
      itemBuilder: (_, _) => const Mv2Surface(
        borderRadius: Mv2Radius.allMd,
        shadowed: false,
        padding: EdgeInsets.all(Mv2Spacing.x3),
        child: Row(
          children: <Widget>[
            Mv2SkeletonBox(width: 44, height: 44, radius: Mv2Radius.allSm),
            SizedBox(width: Mv2Spacing.x3),
            Mv2SkeletonBox(width: 96, height: 16),
            Spacer(),
            Mv2SkeletonBox(width: 48, height: 12),
          ],
        ),
      ),
    );
  }
}
