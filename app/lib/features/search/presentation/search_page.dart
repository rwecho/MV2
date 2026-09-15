import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/models/models.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_refreshable.dart';
import '../../../ui/components/mv2_segmented_tabs.dart';
import '../../../ui/components/node_card.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/components/topic_item.dart';
import '../../../ui/primitives/mv2_avatar.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../../ui/primitives/mv2_chips.dart';
import '../../nodes/application/nodes_providers.dart';
import '../../topic/application/open_topic.dart';
import '../application/search_providers.dart';

/// Search page (`designs/05-search.png`).
///
/// Pushed inside the feed branch (`/feed/search`), so the floating tab bar
/// stays visible underneath and every scrollable reserves
/// [Mv2PageScaffold.bottomContentInset].
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  static const List<String> _segments = <String>['主题', '用户', '节点'];

  /// Sort chips from the design. 仅标题 and 热门 have no sov2ex equivalent and
  /// are rendered but disabled — see [_sortFor].
  static const List<String> _sortLabels = <String>['相关度', '仅标题', '最新', '热门'];

  static const Duration _debounceDuration = Duration(milliseconds: 300);

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  int _segmentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    // Only the clear affordance depends on the raw text, so a repaint is
    // enough; the committed query is debounced.
    if (mounted) setState(() {});
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _commitQuery);
  }

  void _commitQuery() {
    if (!mounted) return;
    ref.read(searchQueryProvider.notifier).setQuery(_controller.text);
  }

  void _clearQuery() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).clear();
  }

  /// Tapping a 最近搜索 chip sets the query and re-promotes the term.
  void _selectRecent(String term) {
    _controller.text = term;
    ref.read(recentSearchesProvider.notifier).add(term);
  }

  void _submitQuery(String value) {
    _debounce?.cancel();
    ref.read(searchQueryProvider.notifier).setQuery(value);
    ref.read(recentSearchesProvider.notifier).add(value);
  }

  /// sov2ex accepts only `sumup` and `created`; 仅标题 (index 1) and 热门
  /// (index 3) have no server-side equivalent, so they map to `null` and their
  /// chips are no-ops.
  // TODO(phase 2C): revisit 热门 once sov2ex exposes a reply-count sort.
  // TODO(phase 2C): 仅标题 needs a client-side title-only filter.
  SearchSort? _sortFor(int index) => switch (index) {
    0 => SearchSort.relevance,
    2 => SearchSort.created,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return Mv2PageScaffold(
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Mv2Spacing.pageNarrow,
              Mv2Spacing.x2,
              Mv2Spacing.pageNarrow,
              Mv2Spacing.x3,
            ),
            child: Row(
              children: <Widget>[
                Expanded(child: _buildQueryField(context)),
                const SizedBox(width: Mv2Spacing.x2),
                Mv2TextButton(label: '取消', onPressed: () => context.pop()),
              ],
            ),
          ),
          Mv2SegmentedTabs(
            items: _segments,
            selectedIndex: _segmentIndex,
            onChanged: (index) => setState(() => _segmentIndex = index),
            padded: true,
          ),
          const SizedBox(height: Mv2Spacing.x3),
        ],
      ),
      child: _buildBody(context),
    );
  }

  Widget _buildQueryField(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: Mv2Spacing.x3),
      decoration: BoxDecoration(
        color: colors.divider,
        borderRadius: Mv2Radius.pill,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, size: 20, color: colors.textTertiary),
          const SizedBox(width: Mv2Spacing.x2),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              cursorColor: colors.accent,
              onSubmitted: _submitQuery,
              style: context.text.bodySmall.copyWith(color: colors.textPrimary),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                // The theme defines focused/enabled borders, and they win over
                // `border` — clear them so the field stays a flat pill.
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: '搜索主题、用户或节点',
                hintStyle: context.text.bodySmall.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _clearQuery,
              child: Padding(
                padding: const EdgeInsets.only(left: Mv2Spacing.x2),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final bottomInset = Mv2PageScaffold.bottomContentInset(context);
    final query = ref.watch(searchQueryProvider).trim();
    final recents = ref.watch(recentSearchesProvider);

    return Mv2Refreshable(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          if (recents.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: Mv2Spacing.pageNarrow,
              ),
              sliver: SliverToBoxAdapter(
                child: _buildRecentSearches(context, recents),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Mv2Spacing.pageNarrow,
              Mv2Spacing.x3,
              Mv2Spacing.pageNarrow,
              0,
            ),
            sliver: SliverToBoxAdapter(child: _buildSortRow()),
          ),
          ..._buildResultSlivers(context, bottomInset, query),
        ],
      ),
    );
  }

  /// Re-runs the result query for the active segment.
  Future<void> _refresh() async {
    switch (_segmentIndex) {
      case 1:
        ref.invalidate(searchUsersProvider);
        await ref.read(searchUsersProvider.future);
      case 2:
        ref.invalidate(searchNodesProvider);
        await ref.read(searchNodesProvider.future);
      default:
        ref.invalidate(searchResultsProvider);
        await ref.read(searchResultsProvider.future);
    }
  }

  Widget _buildRecentSearches(BuildContext context, List<String> recents) {
    final colors = context.colors;

    return Mv2Surface(
      borderRadius: Mv2Radius.allMd,
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '最近搜索',
                  style: context.text.itemTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref.read(recentSearchesProvider.notifier).clear(),
                child: Text(
                  '清空',
                  style: context.text.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Mv2Spacing.x3),
          Wrap(
            spacing: Mv2Spacing.x2,
            runSpacing: Mv2Spacing.x2,
            children: <Widget>[
              for (final term in recents)
                Mv2Chip(
                  label: term,
                  icon: Icons.search_rounded,
                  onTap: () => _selectRecent(term),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortRow() {
    final selected = ref.watch(searchSortProvider);

    return Wrap(
      spacing: Mv2Spacing.x2,
      runSpacing: Mv2Spacing.x2,
      children: <Widget>[
        for (var i = 0; i < _sortLabels.length; i++)
          Builder(
            builder: (context) {
              final sort = _sortFor(i);
              return Mv2Chip(
                label: _sortLabels[i],
                dense: true,
                selected: sort != null && sort == selected,
                // `null` keeps the chip visually present but non-interactive
                // for the unsupported modes.
                onTap: sort == null
                    ? null
                    : () => ref.read(searchSortProvider.notifier).select(sort),
              );
            },
          ),
      ],
    );
  }

  // --------------------------------------------------------------- results

  List<Widget> _buildResultSlivers(
    BuildContext context,
    double bottomInset,
    String query,
  ) {
    // Empty query keeps the 最近搜索 view; no request is issued.
    if (query.isEmpty) return const <Widget>[];

    return switch (_segmentIndex) {
      1 => _watchUsers(context, bottomInset),
      2 => _watchNodes(context, bottomInset),
      _ => _watchTopics(context, bottomInset),
    };
  }

  List<Widget> _watchTopics(BuildContext context, double bottomInset) {
    ref.listen(
      searchResultsProvider,
      (p, n) => mv2ToastLoadError(context, p, n),
    );
    return ref
        .watch(searchResultsProvider)
        .when(
          skipLoadingOnReload: true,
          data: (results) => results.isEmpty
              ? _empty()
              : _listSlivers(context, bottomInset, results.length, (index) {
                  final topic = results[index];
                  return TopicItem(
                    topic: topic,
                    onTap: () => openTopic(context, topic.id),
                  );
                }),
          loading: () => _loading(bottomInset),
          error: (_, _) => _error(() => ref.invalidate(searchResultsProvider)),
        );
  }

  List<Widget> _watchUsers(BuildContext context, double bottomInset) {
    ref.listen(searchUsersProvider, (p, n) => mv2ToastLoadError(context, p, n));
    return ref
        .watch(searchUsersProvider)
        .when(
          skipLoadingOnReload: true,
          data: (users) => users.isEmpty
              ? _empty()
              : _listSlivers(
                  context,
                  bottomInset,
                  users.length,
                  (index) => _buildUserRow(context, users[index]),
                ),
          loading: () => _loading(bottomInset),
          error: (_, _) => _error(() => ref.invalidate(searchUsersProvider)),
        );
  }

  List<Widget> _watchNodes(BuildContext context, double bottomInset) {
    ref.listen(searchNodesProvider, (p, n) => mv2ToastLoadError(context, p, n));
    return ref
        .watch(searchNodesProvider)
        .when(
          skipLoadingOnReload: true,
          data: (nodes) => nodes.isEmpty
              ? _empty()
              : _listSlivers(
                  context,
                  bottomInset,
                  nodes.length,
                  (index) => _buildNodeCard(context, nodes[index]),
                ),
          loading: () => _loading(bottomInset),
          error: (_, _) => _error(() => ref.invalidate(nodesProvider)),
        );
  }

  /// Member row — avatar + username, matching the MV2 list rhythm.
  Widget _buildUserRow(BuildContext context, V2User user) {
    final colors = context.colors;

    return Mv2Surface(
      borderRadius: Mv2Radius.allMd,
      shadowed: false,
      onTap: user.username.isEmpty || user.username == '匿名'
          ? null
          : () => context.push('/member/${user.username}'),
      padding: const EdgeInsets.all(Mv2Spacing.x3),
      child: Row(
        children: <Widget>[
          Mv2Avatar(user: user, size: 36),
          const SizedBox(width: Mv2Spacing.x3),
          Expanded(
            child: Text(
              user.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.itemTitle.copyWith(color: colors.textPrimary),
            ),
          ),
          if (user.id != null)
            Text(
              'V2EX #${user.id}',
              style: context.text.metadata.copyWith(color: colors.textTertiary),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(BuildContext context, V2Node node) {
    return NodeCard(
      node: node,
      onTap: () => context.push(
        '/node/${node.key}?name=${Uri.encodeComponent(node.name)}',
      ),
    );
  }

  List<Widget> _listSlivers(
    BuildContext context,
    double bottomInset,
    int count,
    Widget Function(int index) builder,
  ) {
    return <Widget>[
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          Mv2Spacing.pageNarrow,
          Mv2Spacing.x3,
          Mv2Spacing.pageNarrow,
          bottomInset,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            // Even indices are rows, odd indices are the inter-row gap.
            if (index.isOdd) return const SizedBox(height: Mv2Spacing.x3);
            return builder(index ~/ 2);
          }, childCount: count * 2 - 1),
        ),
      ),
    ];
  }

  List<Widget> _loading(double bottomInset) => <Widget>[
    SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: const TopicListSkeleton(),
      ),
    ),
  ];

  List<Widget> _empty() => <Widget>[
    SliverFillRemaining(
      hasScrollBody: false,
      child: const Mv2StateView(kind: Mv2StateKind.empty),
    ),
  ];

  List<Widget> _error(VoidCallback onRetry) => <Widget>[
    SliverFillRemaining(
      hasScrollBody: false,
      child: Mv2StateView(
        kind: Mv2StateKind.error,
        actionLabel: '重试',
        onAction: onRetry,
      ),
    ),
  ];
}
