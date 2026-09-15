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
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/components/topic_item.dart';
import '../../auth/application/auth_controller.dart';
import '../../topic/application/open_topic.dart';
import '../application/my_providers.dart';
import '../data/my_api.dart';

/// The three 我的 topic lists share one page; only the provider differs.
enum MyListKind {
  topics('我的主题'),
  replies('我的回复'),
  favorites('收藏');

  const MyListKind(this.title);

  final String title;

  String get emptyTitle => switch (this) {
    MyListKind.topics => '还没有发布过主题',
    MyListKind.replies => '还没有回复过主题',
    MyListKind.favorites => '还没有收藏的主题',
  };

  String get emptyDescription => switch (this) {
    MyListKind.topics => '你发布过的主题会出现在这里。',
    MyListKind.replies => '你参与回复过的主题会出现在这里。',
    MyListKind.favorites => '在主题页点击收藏，就会出现在这里。',
  };
}

/// 我的主题 / 我的回复 / 收藏 — a secondary list over the signed-in session.
///
/// Same [TopicItem] metrics as 稍后阅读, with infinite scrolling: the first page
/// comes from the matching provider, later pages are fetched directly from
/// [MyApi] as the list nears its bottom (the pattern of
/// `topic_detail_page.dart#_loadMore`).
class MyTopicListPage extends ConsumerStatefulWidget {
  const MyTopicListPage({super.key, required this.kind});

  final MyListKind kind;

  @override
  ConsumerState<MyTopicListPage> createState() => _MyTopicListPageState();
}

class _MyTopicListPageState extends ConsumerState<MyTopicListPage> {
  /// Distance from the bottom at which the next page starts loading.
  static const double _loadMoreThreshold = 800;

  final ScrollController _scrollController = ScrollController();
  final List<V2Topic> _extra = <V2Topic>[];
  List<V2Topic> _firstTopics = const <V2Topic>[];
  int _loadedPage = 1;
  int _maxPage = 1;
  bool _loadingMore = false;
  bool _reachedEnd = false;
  Object? _moreError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  FutureProvider<MyTopicPage> get _provider => switch (widget.kind) {
    MyListKind.topics => myTopicsProvider,
    MyListKind.replies => myRepliesProvider,
    MyListKind.favorites => favoriteTopicsProvider,
  };

  AsyncValue<MyTopicPage> _watchFirstPage() => ref.watch(_provider);

  Future<MyTopicPage> _fetchPage(int page) => switch (widget.kind) {
    MyListKind.topics => ref.read(myApiProvider).myTopics(page: page),
    MyListKind.replies => ref.read(myApiProvider).myReplies(page: page),
    MyListKind.favorites => ref.read(myApiProvider).favoriteTopics(page: page),
  };

  bool get _hasMore => !_reachedEnd && _loadedPage < _maxPage;

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final next = await _fetchPage(_loadedPage + 1);
      if (!mounted) return;
      setState(() {
        _loadedPage += 1;
        final known = <int>{
          for (final topic in <V2Topic>[..._firstTopics, ..._extra]) topic.id,
        };
        final fresh = next.topics
            .where((topic) => !known.contains(topic.id))
            .toList(growable: false);
        if (fresh.isEmpty) {
          _reachedEnd = true;
        } else {
          _extra.addAll(fresh);
        }
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _moreError = error;
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _extra.clear();
      _loadedPage = 1;
      _reachedEnd = false;
      _moreError = null;
      _loadingMore = false;
    });
    ref.invalidate(_provider);
    await ref.read(_provider.future);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(isSignedInProvider);
    final bottomInset = Mv2PageScaffold.bottomContentInset(context);
    final firstPage = _watchFirstPage();
    ref.listen(_provider, (p, n) => mv2ToastLoadError(context, p, n));

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(
        title: widget.kind.title,
        onBack: () => context.pop(),
      ),
      child: !signedIn
          ? Mv2StateView(
              kind: Mv2StateKind.empty,
              title: '登录后查看',
              description: '登录 V2EX 后即可同步${widget.kind.title}。',
              actionLabel: '去登录',
              onAction: () => context.push('/login'),
            )
          : firstPage.when(
              skipLoadingOnReload: true,
              loading: () => Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: const TopicListSkeleton(),
              ),
              error: (_, _) => Mv2StateView(
                kind: Mv2StateKind.error,
                actionLabel: '重试',
                onAction: () => ref.invalidate(_provider),
              ),
              data: (page) {
                // The provider answer owns the pager window; the scroll
                // listener reads these fields without rebuilding.
                _maxPage = page.pagination.maximum < 1
                    ? 1
                    : page.pagination.maximum;
                _firstTopics = page.topics;
                final topics = <V2Topic>[...page.topics, ..._extra];
                if (topics.isEmpty) {
                  return Mv2StateView(
                    kind: Mv2StateKind.empty,
                    title: widget.kind.emptyTitle,
                    description: widget.kind.emptyDescription,
                  );
                }
                return Mv2Refreshable(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      Mv2Spacing.pageNarrow,
                      0,
                      Mv2Spacing.pageNarrow,
                      bottomInset,
                    ),
                    itemCount: topics.length + 1,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Mv2Spacing.x3),
                    itemBuilder: (context, index) {
                      if (index == topics.length) return _footer(context);
                      final topic = topics[index];
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

  /// Footer under the list: spinner, retry, manual fallback, or end marker.
  Widget _footer(BuildContext context) {
    final colors = context.colors;
    if (_loadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x4),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
            ),
          ),
        ),
      );
    }
    if (_moreError != null) {
      return _NextPageButton(
        label: '加载失败，点击重试',
        onTap: () => unawaited(_loadMore()),
      );
    }
    if (_hasMore) {
      return _NextPageButton(
        label: '加载更多',
        onTap: () => unawaited(_loadMore()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x4),
      child: Center(
        child: Text(
          '没有更多了',
          style: context.text.metadata.copyWith(color: colors.textTertiary),
        ),
      ),
    );
  }
}

/// Manual pagination fallback, matching the topic detail page's button.
class _NextPageButton extends StatelessWidget {
  const _NextPageButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x3),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: Mv2Radius.allMd,
          border: Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: context.text.button.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
