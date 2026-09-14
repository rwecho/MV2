import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/models/models.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_refreshable.dart';
import '../../../ui/components/node_card.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../settings/application/settings_controller.dart';
import '../application/nodes_providers.dart';

/// 全部节点 (`/api/nodes/s2.json`, ~1374 entries) with a client-side filter.
///
/// [nodesProvider] already ranks by topic count, so this page only filters and
/// renders — lazily, through a [ListView.builder], since building all 1374
/// [NodeCard]s at once would stall the frame.
class AllNodesPage extends ConsumerStatefulWidget {
  const AllNodesPage({super.key});

  @override
  ConsumerState<AllNodesPage> createState() => _AllNodesPageState();
}

class _AllNodesPageState extends ConsumerState<AllNodesPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  /// The debounced query actually used for filtering.
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    // Rebuild immediately so the clear affordance tracks the raw text; the
    // filter itself only runs once the 200ms debounce settles.
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  void _clearQuery() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
  }

  /// Matches display name, slug and aliases (the parser exposes the V2EX
  /// `aliases` array through [V2Node.tags]).
  List<V2Node> _filter(List<V2Node> nodes) {
    if (_query.isEmpty) return nodes;
    final String needle = _query.toLowerCase();
    return nodes
        .where(
          (V2Node node) =>
              node.name.toLowerCase().contains(needle) ||
              node.key.toLowerCase().contains(needle) ||
              node.tags.any((String tag) => tag.toLowerCase().contains(needle)),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(nodesProvider);
    ref.listen(nodesProvider, (p, n) => mv2ToastLoadError(context, p, n));
    // The 内容宽度 preference caps the content column on wide viewports.
    final double maxContentWidth = ref.watch(contentMaxWidthProvider);
    final double bottomInset = Mv2PageScaffold.bottomContentInset(context);

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(title: '全部节点', onBack: () => context.pop()),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Mv2Spacing.pageNarrow,
                  0,
                  Mv2Spacing.pageNarrow,
                  Mv2Spacing.x3,
                ),
                child: _NodeSearchField(
                  controller: _controller,
                  onChanged: _onQueryChanged,
                  onClear: _clearQuery,
                ),
              ),
              Expanded(
                child: nodes.when(
                  skipLoadingOnReload: true,
                  loading: () => const _NodeListSkeleton(),
                  error: (_, _) => Mv2StateView(
                    kind: Mv2StateKind.error,
                    actionLabel: '重试',
                    onAction: () => ref.invalidate(nodesProvider),
                  ),
                  data: (List<V2Node> all) {
                    final List<V2Node> filtered = _filter(all);
                    return Mv2Refreshable(
                      onRefresh: () => ref.refresh(nodesProvider.future),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (_query.isNotEmpty)
                            _ResultCount(count: filtered.length),
                          Expanded(
                            child: filtered.isEmpty
                                ? LayoutBuilder(
                                    builder:
                                        (
                                          BuildContext context,
                                          BoxConstraints constraints,
                                        ) => SingleChildScrollView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              minHeight: constraints.maxHeight,
                                            ),
                                            child: const Mv2StateView(
                                              kind: Mv2StateKind.empty,
                                              title: '没有找到相关节点',
                                              description: '换个关键词试试。',
                                            ),
                                          ),
                                        ),
                                  )
                                : ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior
                                            .onDrag,
                                    padding: EdgeInsets.fromLTRB(
                                      Mv2Spacing.pageNarrow,
                                      0,
                                      Mv2Spacing.pageNarrow,
                                      bottomInset,
                                    ),
                                    itemCount: filtered.length,
                                    itemBuilder: (BuildContext context, int index) {
                                      final V2Node node = filtered[index];
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          bottom: index == filtered.length - 1
                                              ? 0
                                              : Mv2Spacing.x3,
                                        ),
                                        child: NodeCard(
                                          node: node,
                                          onTap: () => context.push(
                                            '/node/${node.key}?name=${Uri.encodeComponent(node.name)}',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Focused search input — the page is opened from the 节点 page's search
/// affordance, so the field takes focus on arrival.
class _NodeSearchField extends StatelessWidget {
  const _NodeSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: context.text.body.copyWith(color: colors.textPrimary),
      decoration: InputDecoration(
        hintText: '搜索节点',
        isDense: true,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: colors.textTertiary,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: Mv2Spacing.minTapTarget,
          minHeight: Mv2Spacing.minTapTarget,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colors.textTertiary,
                ),
              ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: Mv2Spacing.minTapTarget,
          minHeight: Mv2Spacing.minTapTarget,
        ),
      ),
    );
  }
}

/// `共 N 个节点` — only rendered while a filter is active.
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Mv2Spacing.pageNarrow,
        0,
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x3,
      ),
      child: Text(
        '共 $count 个节点',
        style: context.text.metadata.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

/// Loading placeholder matching [NodeCard] metrics.
class _NodeListSkeleton extends StatelessWidget {
  const _NodeListSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: Mv2Spacing.pageNarrow),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: Mv2Spacing.x3),
      itemBuilder: (_, _) => Container(
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
                  Mv2SkeletonBox(width: 140, height: 16),
                  SizedBox(height: Mv2Spacing.x3),
                  Mv2SkeletonBox(width: double.infinity, height: 12),
                  SizedBox(height: Mv2Spacing.x1),
                  Mv2SkeletonBox(width: 180, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
