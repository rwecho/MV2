import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/session_once.dart';
import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_motion.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/topic_detail.dart';
import '../../../ui/components/floating_reply_bar.dart';
import '../../../ui/components/mv2_collapsible_body.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_rich_text.dart';
import '../../../ui/components/mv2_scroll_collapse.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/components/topic_action_bar.dart';
import '../../../ui/mv2_haptics.dart';
import '../../../ui/primitives/mv2_avatar.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../../ui/primitives/mv2_chips.dart';
import '../../blocked/application/blocked_content.dart';
import '../../blocked/application/blocked_users_controller.dart';
import '../../composer/presentation/composer_sheets.dart';
import '../../settings/application/settings_controller.dart';
import '../../shell/application/tablet_topic_pane.dart';
import '../application/topic_actions.dart';
import '../application/topic_providers.dart';

/// Native share sheet for a topic: `标题  https://www.v2ex.com/t/{id}`.
///
/// Sharing is read-only, so it is available signed out. If the platform share
/// channel is unavailable (plugin not registered after a hot reload, a desktop
/// build without a share target, …) the link is copied to the clipboard instead
/// of leaving the user with a dead end.
Future<void> _shareTopic(BuildContext context, V2Topic topic) async {
  final text = '${topic.title}  https://www.v2ex.com/t/${topic.id}';
  try {
    // Anchor the iPad/Mac popover to the invoking widget (ignored on iPhone).
    final box = context.findRenderObject() as RenderBox?;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
  } catch (error, stackTrace) {
    debugPrint('MV2: share failed: $error\n$stackTrace');
    // Best-effort clipboard fallback; a clipboard failure must not hide the
    // message below.
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('无法打开分享面板，链接已复制到剪贴板')));
  }
}

/// Report a topic by opening the legacy `report@v2ex.maui` address with the
/// topic id/title prefilled in the subject (URL-encoded by [Uri]).
Future<void> _reportTopic(BuildContext context, V2Topic topic) async {
  final uri = Uri(
    scheme: 'mailto',
    path: 'report@v2ex.maui',
    queryParameters: <String, String>{
      'subject': '举报主题 #${topic.id} ${topic.title}',
    },
  );
  var opened = false;
  try {
    opened = await launchUrl(uri);
  } catch (_) {
    opened = false;
  }
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('无法打开邮件应用')));
}

/// Report a single reply through the same `report@v2ex.maui` mailto channel as
/// topic reports, prefilling the floor / author / reply id.
Future<void> _reportReply(
  BuildContext context,
  int topicId,
  V2Reply reply,
) async {
  final uri = Uri(
    scheme: 'mailto',
    path: 'report@v2ex.maui',
    queryParameters: <String, String>{
      'subject': '举报回复 #${reply.floor} @${reply.author.username}',
      'body':
          '主题：https://www.v2ex.com/t/$topicId\n'
          '楼层：#${reply.floor}\n'
          '作者：@${reply.author.username}\n'
          '回复 ID：${reply.id ?? '-'}\n\n'
          '举报原因：',
    },
  );
  var opened = false;
  try {
    opened = await launchUrl(uri);
  } catch (_) {
    opened = false;
  }
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('无法打开邮件应用')));
}

/// Topic detail (`designs/02-topic-detail.png`).
///
/// The article is fetched through [topicDetailProvider] so the page can render
/// a skeleton while loading and a retryable error state on failure.
///
/// Reading down docks the topic title into the top bar and slides the reply bar
/// away; scrolling back restores both.
class TopicDetailPage extends ConsumerStatefulWidget {
  const TopicDetailPage({
    super.key,
    required this.topicId,
    this.initialFloor,
    this.inPane = false,
  });

  final int topicId;

  /// Reply floor to scroll to once loaded (`/topic/123?floor=4`).
  final int? initialFloor;

  /// Rendered inside the tablet layout's right-hand pane rather than as a
  /// pushed route: the back affordance then closes the pane (there is no
  /// route to pop).
  final bool inPane;

  @override
  ConsumerState<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends ConsumerState<TopicDetailPage> {
  bool _collapsed = false;

  bool _onScrollNotification(ScrollNotification notification) {
    final collapsed = mv2CollapseFromScroll(notification);
    if (collapsed != null && collapsed != _collapsed) {
      setState(() => _collapsed = collapsed);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final args = TopicDetailArgs(widget.topicId);
    final detail = ref.watch(topicDetailProvider(args));

    return Mv2PageScaffold(
      header: _TopicDetailTopBar(
        topicId: widget.topicId,
        collapsed: _collapsed,
        inPane: widget.inPane,
      ),
      bottomBar: AnimatedSlide(
        // 1.2× the reply bar height clears its own safe-area padding.
        offset: _collapsed ? const Offset(0, 1.2) : Offset.zero,
        duration: Mv2Motion.sheet,
        curve: Mv2Motion.standard,
        child: FloatingReplyBar(
          placeholder: '写下你的回复...',
          onTap: () => showReplyComposer(context, topicId: widget.topicId),
        ),
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: detail.when(
          loading: () => const _TopicArticleSkeleton(),
          error: (error, stackTrace) => error is AuthFailure
              // Restricted / login-only topic: V2EX answers `302 → /restricted
              // → /signin?next=/restricted`. A 重试 button can never succeed
              // while signed out, so offer the sign-in route instead.
              ? Mv2StateView(
                  kind: Mv2StateKind.error,
                  title: '该主题需要登录后查看',
                  description: '登录 V2EX 账号后即可查看该主题的正文与回复。',
                  actionLabel: '去登录',
                  onAction: () => context.push('/login'),
                )
              : Mv2StateView(
                  kind: Mv2StateKind.error,
                  actionLabel: '重试',
                  onAction: () => ref.invalidate(topicDetailProvider(args)),
                ),
          data: (data) => _TopicDetailBody(
            topicId: widget.topicId,
            detail: data,
            initialFloor: widget.initialFloor,
          ),
        ),
      ),
    );
  }
}

/// Compact non-centred top bar: back on the left, overflow on the right.
///
/// When [collapsed] the centre fades in the topic title, so the article's title
/// follows the reader into the bar once it scrolls out of view. The overflow
/// (`⋯`) opens the 忽略 / 举报 sheet; the 忽略 state comes from
/// [topicActionsProvider] so it stays in sync with the action controller.
class _TopicDetailTopBar extends ConsumerWidget {
  const _TopicDetailTopBar({
    required this.topicId,
    required this.collapsed,
    this.inPane = false,
  });

  final int topicId;
  final bool collapsed;

  /// Mirrors [TopicDetailPage.inPane]: close the pane instead of popping.
  final bool inPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final title = ref
        .watch(topicDetailProvider(TopicDetailArgs(topicId)))
        .value
        ?.topic
        .title;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Mv2Spacing.x1,
        vertical: Mv2Spacing.x1,
      ),
      child: Row(
        children: <Widget>[
          Mv2IconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onPressed: inPane
                // Dismiss the tablet detail pane (no pushed route to pop).
                ? () => ProviderScope.containerOf(context, listen: false)
                    .read(tabletTopicPaneProvider.notifier)
                    .close()
                : () => context.pop(),
          ),
          Expanded(
            child: AnimatedOpacity(
              opacity: collapsed ? 1 : 0,
              duration: Mv2Motion.tab,
              curve: Mv2Motion.standard,
              child: Text(
                title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.text.itemTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          Mv2IconButton(
            icon: Icons.more_horiz_rounded,
            onPressed: () => _showOverflowSheet(context, ref),
          ),
        ],
      ),
    );
  }

  void _showOverflowSheet(BuildContext context, WidgetRef ref) {
    final detail = ref
        .read(topicDetailProvider(TopicDetailArgs(topicId)))
        .value;
    final ignored = ref
        .read(topicActionsProvider(topicId))
        .ignoredOf(detail?.ignored ?? false);
    final signedIn = detail?.canReply ?? false;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.elevatedSurface,
      shape: const RoundedRectangleBorder(borderRadius: Mv2Radius.allXl),
      builder: (BuildContext sheetContext) => _TopicOverflowSheet(
        ignored: ignored,
        onShare: () {
          Navigator.of(sheetContext).pop();
          final topic = detail?.topic;
          if (topic != null) unawaited(_shareTopic(context, topic));
        },
        onIgnore: () {
          Navigator.of(sheetContext).pop();
          if (!signedIn) {
            context.push('/login');
            return;
          }
          unawaited(
            ref.read(topicActionsProvider(topicId).notifier).toggleIgnore(),
          );
        },
        onReport: () {
          Navigator.of(sheetContext).pop();
          final topic = detail?.topic;
          if (topic != null) unawaited(_reportTopic(context, topic));
        },
      ),
    );
  }
}

/// Bottom sheet shared by the topic overflow actions. Mirrors the settings
/// `_SelectionSheet` metrics (title padding + ≥48px option rows).
class _TopicOverflowSheet extends StatelessWidget {
  const _TopicOverflowSheet({
    required this.ignored,
    required this.onShare,
    required this.onIgnore,
    required this.onReport,
  });

  final bool ignored;
  final VoidCallback onShare;
  final VoidCallback onIgnore;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Mv2Spacing.x4,
              Mv2Spacing.x5,
              Mv2Spacing.x4,
              Mv2Spacing.x2,
            ),
            child: Text(
              '更多操作',
              style: context.text.sectionTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          _SheetOption(
            icon: Icons.ios_share_rounded,
            label: '分享',
            onTap: onShare,
          ),
          _SheetOption(
            icon: ignored
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            label: ignored ? '取消忽略' : '忽略主题',
            onTap: onIgnore,
          ),
          _SheetOption(
            icon: Icons.flag_outlined,
            label: '举报',
            danger: true,
            onTap: onReport,
          ),
          const SizedBox(height: Mv2Spacing.x3),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = danger ? colors.danger : colors.textPrimary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Mv2Spacing.minTapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x4,
          vertical: Mv2Spacing.x3,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 20,
              color: danger ? colors.danger : colors.textSecondary,
            ),
            const SizedBox(width: Mv2Spacing.x3),
            Expanded(
              child: Text(label, style: context.text.body.copyWith(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Long-press action sheet for a single reply — mirrors the topic overflow
/// sheet's metrics and reuses [_SheetOption].
class _ReplyActionsSheet extends StatelessWidget {
  const _ReplyActionsSheet({
    required this.floor,
    required this.canCopy,
    required this.onReply,
    required this.onCopy,
    required this.onReport,
  });

  final int floor;
  final bool canCopy;
  final VoidCallback onReply;
  final VoidCallback onCopy;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Mv2Spacing.x4,
              Mv2Spacing.x5,
              Mv2Spacing.x4,
              Mv2Spacing.x2,
            ),
            child: Text(
              '#$floor 的回复',
              style: context.text.sectionTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          _SheetOption(icon: Icons.reply_rounded, label: '回复', onTap: onReply),
          if (canCopy)
            _SheetOption(icon: Icons.copy_rounded, label: '复制', onTap: onCopy),
          _SheetOption(
            icon: Icons.flag_outlined,
            label: '举报',
            danger: true,
            onTap: onReport,
          ),
          const SizedBox(height: Mv2Spacing.x3),
        ],
      ),
    );
  }
}

/// Scrollable article + replies. Holds the local 收藏 / 感谢 overrides on top of
/// the server state from [V2TopicDetail] so the page itself can stay a stateless
/// [ConsumerWidget].
class _TopicDetailBody extends ConsumerStatefulWidget {
  const _TopicDetailBody({
    required this.topicId,
    required this.detail,
    this.initialFloor,
  });

  final int topicId;
  final V2TopicDetail detail;
  final int? initialFloor;

  @override
  ConsumerState<_TopicDetailBody> createState() => _TopicDetailBodyState();
}

class _TopicDetailBodyState extends ConsumerState<_TopicDetailBody> {
  // 收藏 / 感谢 / 忽略 state lives in [topicActionsProvider] so it can be
  // rolled back on failure; the server flags from `widget.detail` are the base.

  // V2EX serves replies 100 per page via `?p=N` (verified against live
  // markup: a 169-reply topic reports `max="2"`), so no page-size math is
  // needed — the server's `maximum` drives everything.

  /// Distance from the bottom at which the next page starts loading.
  static const double _loadMoreThreshold = 800;

  final ScrollController _scrollController = ScrollController();
  final List<V2Reply> _extraReplies = <V2Reply>[];
  late int _page = widget.detail.pagination.current;
  bool _loadingMore = false;
  bool _reachedEnd = false;
  Object? _moreError;

  /// Floor currently tinted after a `@user #5` reference scrolled to it.
  int? _highlightedFloor;
  Timer? _highlightTimer;

  /// Stable key per floor so [_jumpToFloor] can measure and reveal a row.
  final Map<int, GlobalKey> _replyKeys = <int, GlobalKey>{};

  /// floor → index into [_replies]; rebuilt on every build.
  final Map<int, int> _replyIndexByFloor = <int, int>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final floor = widget.initialFloor;
    if (floor != null) {
      // After the first layout so `_replyIndexByFloor` is populated.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_jumpToFloor(floor, ensureLoaded: true));
      });
    }
  }

  @override
  void didUpdateWidget(covariant _TopicDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pull-to-refresh replaces the first page; drop the accumulated pages.
    if (oldWidget.detail != widget.detail) {
      _extraReplies.clear();
      _page = widget.detail.pagination.current;
      _reachedEnd = false;
      _moreError = null;
      _loadingMore = false;
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasMore => widget.detail.pagination.maximum > _page && !_reachedEnd;

  /// All replies known so far: first page plus every loaded page.
  List<V2Reply> get _replies => <V2Reply>[
    ...widget.detail.replies,
    ..._extraReplies,
  ];

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
      final next = await ref
          .read(v2exApiProvider)
          .topicDetail(widget.topicId, page: _page + 1);
      // Rendering page N+1 rotates the session `once`; keep the newest one so
      // an action right after scrolling is not rejected.
      ref.read(sessionOnceProvider.notifier).update(next.once);
      if (!mounted) return;
      setState(() {
        _page = next.pagination.current > _page
            ? next.pagination.current
            : _page + 1;
        // Deduplicate: V2EX can shift floors when replies are deleted.
        final known = <String>{
          for (final reply in _replies) reply.id ?? 'f${reply.floor}',
        };
        final fresh = next.replies
            .where((reply) => !known.contains(reply.id ?? 'f${reply.floor}'))
            .toList(growable: false);
        if (fresh.isEmpty) {
          _reachedEnd = true;
        } else {
          _extraReplies.addAll(fresh);
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
    ref.invalidate(topicDetailProvider(TopicDetailArgs(widget.topicId)));
    await ref.read(topicDetailProvider(TopicDetailArgs(widget.topicId)).future);
  }

  // ------------------------------------------------------- floor references

  /// Scrolls to the reply at [floor] and flashes it, so a body `@user #5`
  /// reference lands on the comment it points at.
  ///
  /// A quote always points at an *earlier* reply, which the incremental loader
  /// has already fetched; the hard part is scrolling, because a lazy list has
  /// no element for an off-screen row. Deep links (`ensureLoaded`) may point at
  /// a later page, so they page forward until the floor is known.
  Future<void> _jumpToFloor(int floor, {bool ensureLoaded = false}) async {
    if (ensureLoaded) {
      for (
        var guard = 0;
        guard < 20 && _replyIndexByFloor[floor] == null;
        guard++
      ) {
        if (!_hasMore || _loadingMore) break;
        await _loadMore();
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    if (_replyIndexByFloor[floor] == null) return;
    final key = _replyKeys[floor];
    if (key == null) return;

    await _revealReply(_replyIndexByFloor[floor]!, key);
    if (!mounted) return;

    _highlightTimer?.cancel();
    setState(() => _highlightedFloor = floor);
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightedFloor = null);
    });
  }

  /// Reveals the row [key] belongs to, estimating its offset from the reply
  /// rows that are currently mounted and refining until it is built.
  Future<void> _revealReply(int replyIndex, GlobalKey key) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!mounted) return;
      final targetContext = key.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.2,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final estimate = _estimateOffsetForReply(replyIndex);
      // Without two mounted anchors, fall back to a proportional guess; either
      // way the next loop iteration corrects once the row is built.
      final target =
          estimate ??
          (replyIndex / (_replyIndexByFloor.length + 1)) *
              position.maxScrollExtent;
      _scrollController.jumpTo(target.clamp(0.0, position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Linear estimate of the offset that reveals reply [replyIndex], fitted to
  /// two currently mounted reply rows (bracketing it when possible).
  double? _estimateOffsetForReply(int replyIndex) {
    final anchors = <(int, double)>[];
    for (final entry in _replyIndexByFloor.entries) {
      final box = _replyKeys[entry.key]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final viewport = RenderAbstractViewport.of(box);
      anchors.add((entry.value, viewport.getOffsetToReveal(box, 0.0).offset));
    }
    if (anchors.length < 2) return null;
    anchors.sort((a, b) => a.$1.compareTo(b.$1));

    var lower = anchors.first;
    var upper = anchors.last;
    for (var i = 0; i < anchors.length - 1; i++) {
      if (anchors[i].$1 <= replyIndex && anchors[i + 1].$1 >= replyIndex) {
        lower = anchors[i];
        upper = anchors[i + 1];
        break;
      }
    }
    if (lower.$1 == upper.$1) return lower.$2;
    final slope = (upper.$2 - lower.$2) / (upper.$1 - lower.$1);
    return lower.$2 + (replyIndex - lower.$1) * slope;
  }

  /// Signed-out sessions are routed to the login page before any request is
  /// attempted; the controller keeps the same guard as a safety net.
  bool get _signedIn => widget.detail.canReply;

  void _onFavorite() {
    if (!_signedIn) {
      context.push('/login');
      return;
    }
    _runWithHaptics(
      () => ref.read(topicActionsProvider(widget.topicId).notifier).toggleFavorite(),
    );
  }

  void _onThankTopic() {
    if (!_signedIn) {
      context.push('/login');
      return;
    }
    _runWithHaptics(
      () => ref.read(topicActionsProvider(widget.topicId).notifier).thankTopic(),
    );
  }

  /// Runs a write and taps the haptics engine only when it actually succeeded —
  /// a rejection (rate limit, expired session) should not feel like a success.
  /// 设置 → 触觉反馈 gates it.
  void _runWithHaptics(Future<Failure?> Function() action) {
    unawaited(() async {
      final failure = await action();
      if (!mounted || failure != null) return;
      Mv2Haptics.success(ref.read(settingsProvider).hapticsEnabled);
    }());
  }

  /// Sharing needs no session — always available.
  void _onShare() {
    unawaited(_shareTopic(context, widget.detail.topic));
  }

  /// `@someone` in a reply means "replying to that member's earlier comment",
  /// so tapping it jumps to that comment — the same destination as an explicit
  /// `#N` reference. Only when the member has no earlier reply (a bare greeting)
  /// does it fall back to their profile.
  void _onMentionTap(V2Reply source, String username) {
    final target = mv2ResolveMentionTarget(
      sourceFloor: source.floor,
      username: username,
      replies: _replies,
    );
    if (target == null) {
      context.push('/member/${Uri.encodeComponent(username)}');
      return;
    }
    unawaited(_jumpToFloor(target.floor));
  }

  /// Opens the composer quoting [reply] as a modal sheet, carrying the tapped
  /// reply so a quote from an infinite-scrolled page still renders (the provider
  /// cache only holds page 1) plus a `#floor` disambiguator when a bare `@user`
  /// would be ambiguous.
  void _openComposerFor(V2Reply reply) {
    showReplyComposer(
      context,
      topicId: widget.topicId,
      floor: reply.floor,
      quotedReply: reply,
      initialText: _replyPrefill(reply),
    );
  }

  /// `#5 ` when the referenced author has several replies, or when later pages
  /// are still unloaded and could hold more. V2EX does not record the reply
  /// target, so V2EX Polish seeds the same marker on the client (its
  /// `processActions`); with it, `@user #5` is unambiguous.
  String? _replyPrefill(V2Reply reply) => mv2ReplyFloorPrefill(
    author: reply.author.username,
    floor: reply.floor,
    replies: _replies,
    hasMore: _hasMore,
  );

  void _onThankReply(String replyId) {
    if (!_signedIn) {
      context.push('/login');
      return;
    }
    _runWithHaptics(
      () => ref
          .read(topicActionsProvider(widget.topicId).notifier)
          .thankReply(replyId),
    );
  }

  /// Long-press sheet for one reply: 回复 / 复制 / 举报.
  Future<void> _showReplyActions(V2Reply reply) async {
    final canCopy = reply.content.trim().isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.elevatedSurface,
      shape: const RoundedRectangleBorder(borderRadius: Mv2Radius.allXl),
      builder: (BuildContext sheetContext) => _ReplyActionsSheet(
        floor: reply.floor,
        canCopy: canCopy,
        onReply: () {
          Navigator.of(sheetContext).pop();
          _openComposerFor(reply);
        },
        onCopy: () {
          Navigator.of(sheetContext).pop();
          unawaited(_copyReply(reply));
        },
        onReport: () {
          Navigator.of(sheetContext).pop();
          unawaited(_reportReply(context, widget.topicId, reply));
        },
      ),
    );
  }

  Future<void> _copyReply(V2Reply reply) async {
    await Clipboard.setData(ClipboardData(text: reply.content));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制回复内容')));
  }

  /// Footer under the reply list: spinner while loading, retry on failure,
  /// manual fallback button, or the end-of-list marker.
  List<Widget> _footerWidgets(BuildContext context) {
    final colors = context.colors;
    final gap = const SizedBox(height: Mv2Spacing.x5);

    if (_loadingMore) {
      return <Widget>[
        gap,
        Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
            ),
          ),
        ),
      ];
    }
    if (_moreError != null) {
      return <Widget>[
        gap,
        _NextPageButton(
          label: '加载失败，点击重试',
          onTap: () => unawaited(_loadMore()),
        ),
      ];
    }
    if (_hasMore) {
      return <Widget>[
        gap,
        _NextPageButton(label: '加载更多回复', onTap: () => unawaited(_loadMore())),
      ];
    }
    if (_replies.isNotEmpty) {
      return <Widget>[
        gap,
        Center(
          child: Text(
            '没有更多回复了',
            style: context.text.metadata.copyWith(color: colors.textTertiary),
          ),
        ),
      ];
    }
    return const <Widget>[];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final detail = widget.detail;
    final topic = detail.topic;
    final contentHtml = detail.contentHtml;
    final actions = ref.watch(topicActionsProvider(widget.topicId));

    // Surface failures once: an expired session routes to /login, anything else
    // (anti-flood, rejection) shows its own message.
    ref.listen(topicActionsProvider(widget.topicId).select((s) => s.failure), (
      previous,
      next,
    ) {
      if (next == null || next == previous) return;
      if (next is AuthFailure) {
        context.push('/login');
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(next.message)));
    });

    // 屏蔽用户 is a local preference (docs/13 Phase 5), and 默认回复排序 decides
    // whether floors or 感谢数 lead. `_replyIndexByFloor` is rebuilt from this
    // list, so `#N` jumps keep working under either ordering.
    final settings = ref.watch(settingsProvider);
    final visible = BlockedContent.replies(
      ref.watch(blockedUsersProvider),
      _replies,
    );
    final replies = switch (settings.replySort) {
      Mv2ReplySort.time => visible,
      Mv2ReplySort.likes => <V2Reply>[...visible]
        ..sort((V2Reply a, V2Reply b) => b.likes.compareTo(a.likes)),
    };
    // Floor → first row index; also guards the per-floor `GlobalKey` so a floor
    // V2EX repeated (it can shift floors when replies are deleted) never puts
    // the same key on two rows.
    _replyIndexByFloor.clear();
    final seenFloors = <int>{};

    // Flatten the body into addressable rows so `ListView.builder` mounts only
    // the visible ones (true virtualization) and `_jumpToFloor` can target a
    // reply by its index.
    final rows = <_BodyRow>[
      _BodyRow(
        () => Mv2Surface(
          padding: const EdgeInsets.all(Mv2Spacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Mv2NodeBadge(node: topic.node),
              const SizedBox(height: Mv2Spacing.x3),
              Text(
                topic.title,
                style: context.text.topicTitleLarge.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: Mv2Spacing.x3),
              _AuthorRow(topic: topic, viewCountLabel: detail.statsLabel),
              if (contentHtml != null) ...<Widget>[
                const SizedBox(height: Mv2Spacing.x4),
                Mv2RichText(html: contentHtml),
              ],
              ..._supplementWidgets(context),
              if (topic.linkPreview != null) ...<Widget>[
                const SizedBox(height: Mv2Spacing.x4),
                _LinkPreviewCard(preview: topic.linkPreview!),
              ],
              const SizedBox(height: Mv2Spacing.x4),
              TopicActionBar(
                favorited: actions.favoritedOf(detail.favorited),
                thanked: actions.thankedOf(detail.thanked),
                thankCount: 0,
                onFavorite: _onFavorite,
                onThank: _onThankTopic,
                onShare: _onShare,
              ),
            ],
          ),
        ),
      ),
      _BodyRow(() => const SizedBox(height: Mv2Spacing.x5)),
      _BodyRow(
        () => _ReplySectionHeader(
          label: detail.replyStatsLabel ?? '${replies.length} 条回复',
        ),
      ),
      _BodyRow(() => const SizedBox(height: Mv2Spacing.x3)),
      _BodyRow(() => Container(height: 1, color: colors.divider)),
    ];

    for (var i = 0; i < replies.length; i++) {
      final reply = replies[i];
      final replyId = reply.id;
      // The first row for a floor owns its key and is the jump target.
      final isFirstOfFloor = seenFloors.add(reply.floor);
      if (isFirstOfFloor) _replyIndexByFloor[reply.floor] = i;
      final floorKey = isFirstOfFloor
          ? _replyKeys.putIfAbsent(reply.floor, () => GlobalKey())
          : null;
      final thankKey = replyId == null
          ? null
          : TopicActionsController.thankReplyKey(replyId);
      final thanking = thankKey != null && actions.isInFlight(thankKey);
      final thanked =
          reply.thanked ||
          (replyId != null && actions.thankedReplies.contains(replyId));
      rows.add(
        _BodyRow(
          () => _ReplyRow(
            key: floorKey,
            reply: reply,
            thanked: thanked,
            highlighted: _highlightedFloor == reply.floor,
            // 设置 → 自动折叠长回复.
            collapsible:
                settings.autoCollapseReplies && reply.content.length > 240,
            // A null id cannot be thanked; an in-flight one is disabled.
            onThank: (replyId == null || thanking)
                ? null
                : () => _onThankReply(replyId),
            onQuote: () => _openComposerFor(reply),
            onLongPress: () => unawaited(_showReplyActions(reply)),
            onMentionTap: (username) => _onMentionTap(reply, username),
            onFloorRefTap: (floor) => unawaited(_jumpToFloor(floor)),
          ),
        ),
      );
      if (i != replies.length - 1) {
        rows.add(_BodyRow(() => Container(height: 1, color: colors.divider)));
      }
    }
    for (final widget in _footerWidgets(context)) {
      rows.add(_BodyRow(() => widget));
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: colors.accent,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          Mv2Spacing.pageNarrow,
          Mv2Spacing.x3,
          Mv2Spacing.pageNarrow,
          Mv2PageScaffold.bottomContentInset(context) + FloatingReplyBar.height,
        ),
        itemCount: rows.length,
        itemBuilder: (context, index) => rows[index].build(),
      ),
    );
  }

  /// Quiet `附言` blocks rendered between the body and the action bar.
  List<Widget> _supplementWidgets(BuildContext context) {
    final colors = context.colors;
    final widgets = <Widget>[];
    for (final supplement in widget.detail.supplements) {
      final html = supplement.contentHtml;
      if (html == null) continue;
      widgets.add(const SizedBox(height: Mv2Spacing.x4));
      widgets.add(
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Mv2Spacing.x2,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: Mv2Radius.allXs,
              ),
              child: Text(
                '附言',
                style: context.text.badge.copyWith(color: colors.textSecondary),
              ),
            ),
            if (supplement.createdAtLabel != null) ...<Widget>[
              const SizedBox(width: Mv2Spacing.x2),
              Text(
                supplement.createdAtLabel!,
                style: context.text.metadata.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      );
      widgets.add(const SizedBox(height: Mv2Spacing.x2));
      widgets.add(
        Mv2RichText(
          html: html,
          baseStyle: context.text.readingSmall.copyWith(
            color: colors.textSecondary,
          ),
        ),
      );
    }
    return widgets;
  }
}

/// Avatar + `author · time` on the left, optional view count on the right.
class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.topic, this.viewCountLabel});

  final V2Topic topic;
  final String? viewCountLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = topic.author.username;
    final canOpen = name.isNotEmpty && name != '匿名';

    return Row(
      children: <Widget>[
        // Only the avatar + name are the tap target; `Align` keeps the row's
        // right-aligned view count intact while the opaque detector covers just
        // the author block.
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canOpen ? () => context.push('/member/$name') : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Mv2Avatar(user: topic.author, size: 22),
                  const SizedBox(width: Mv2Spacing.x2),
                  Flexible(
                    child: Text(
                      '$name · ${topic.createdAtLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.metadata.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (viewCountLabel != null) ...<Widget>[
          Icon(Icons.visibility_outlined, size: 15, color: colors.textTertiary),
          const SizedBox(width: Mv2Spacing.x1),
          Text(
            viewCountLabel!,
            style: context.text.metadata.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// Inline link preview card (icon tile + title + description + url).
class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({required this.preview});

  final V2LinkPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Mv2Surface(
      borderRadius: Mv2Radius.allMd,
      shadowed: false,
      padding: const EdgeInsets.all(Mv2Spacing.x3),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: Mv2Radius.allSm,
            ),
            child: Icon(
              Icons.description_outlined,
              size: 20,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: Mv2Spacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  preview.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.itemTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: Mv2Spacing.x1),
                Text(
                  preview.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Mv2Spacing.x1),
                Text(
                  preview.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.metadata.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Mv2Spacing.x2),
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

/// `#5 ` when [author] has several replies in [replies], or when [hasMore]
/// pages could still hold another.
///
/// With one author reply and everything loaded, a bare `@user` is already
/// unambiguous, so nothing is seeded. Exposed for tests.
@visibleForTesting
String? mv2ReplyFloorPrefill({
  required String author,
  required int floor,
  required Iterable<V2Reply> replies,
  required bool hasMore,
}) {
  final sameAuthor = replies.where((r) => r.author.username == author).length;
  if (sameAuthor <= 1 && !hasMore) return null;
  return '#$floor ';
}

/// The reply a bare `@username` points at: the member's most recent reply
/// before [sourceFloor]. V2EX does not record the reply target, so this is the
/// same "nearest earlier reply by that author" heuristic V2EX Polish uses.
///
/// [replies] is ordered by floor ascending; the scan stops at [sourceFloor].
@visibleForTesting
V2Reply? mv2ResolveMentionTarget({
  required int sourceFloor,
  required String username,
  required Iterable<V2Reply> replies,
}) {
  V2Reply? target;
  for (final reply in replies) {
    if (reply.floor >= sourceFloor) break;
    if (reply.author.username == username) target = reply;
  }
  return target;
}

/// One addressable row in the topic body.
///
/// Keeping the body as a lazy builder (instead of an eager `children:` list)
/// lets `ListView.builder` mount only visible rows, and lets [_TopicDetailBody]
/// scroll to a reply by index for `@user #5` references.
class _BodyRow {
  const _BodyRow(this.build);

  final Widget Function() build;
}

/// Reply row mirroring `ReplyItem` metrics, but able to render V2EX HTML.
class _ReplyRow extends StatelessWidget {
  const _ReplyRow({
    super.key,
    required this.reply,
    required this.thanked,
    this.highlighted = false,
    this.collapsible = false,
    this.onThank,
    this.onQuote,
    this.onLongPress,
    this.onMentionTap,
    this.onFloorRefTap,
  });

  final V2Reply reply;
  final bool thanked;

  /// Briefly tints the row after a floor reference scrolls to it.
  final bool highlighted;

  /// Clamps long bodies behind 展开全文 (设置 → 自动折叠长回复).
  final bool collapsible;
  final VoidCallback? onThank;
  final VoidCallback? onQuote;

  /// Opens the reply action sheet (回复 / 复制 / 举报).
  final VoidCallback? onLongPress;

  /// `@someone` inside the body means "replying to that member's comment", so
  /// tapping it replies to that comment instead of opening a profile.
  final ValueChanged<String>? onMentionTap;

  /// `@someone #5` inside the body jumps to floor 5.
  final ValueChanged<int>? onFloorRefTap;

  /// In-app member page for this reply's author; `null` for anonymous rows.
  String? get _memberRoute {
    final username = reply.author.username.trim();
    if (username.isEmpty || username == '匿名') return null;
    return '/member/${Uri.encodeComponent(username)}';
  }

  /// Wraps the body in the collapse clamp when the row is long and the user
  /// kept 自动折叠长回复 on.
  Widget _body(Widget child) =>
      collapsible ? Mv2CollapsibleBody(child: child) : child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = context.text.readingSmall.copyWith(
      color: colors.textPrimary,
    );
    final contentHtml = reply.contentHtml;
    final memberRoute = _memberRoute;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: Mv2Motion.tab,
        curve: Mv2Motion.standard,
        color: highlighted
            ? colors.accentSoft
            // 楼主 (OP) replies are tinted very lightly so they stand out while
            // scrolling without competing with the content.
            : reply.isOwner
            ? colors.accent.withValues(alpha: 0.045)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Mv2Spacing.x4,
            vertical: Mv2Spacing.x4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: memberRoute == null
                    ? null
                    : () => context.push(memberRoute),
                child: Mv2Avatar(user: reply.author, size: 34),
              ),
              const SizedBox(width: Mv2Spacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: memberRoute == null
                                ? null
                                : () => context.push(memberRoute),
                            child: Text(
                              '@${reply.author.username}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyStrong.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        for (final badge in reply.badges) ...<Widget>[
                          const SizedBox(width: Mv2Spacing.x1),
                          _ReplyBadge(label: badge),
                        ],
                        const SizedBox(width: Mv2Spacing.x2),
                        Text(
                          '#${reply.floor} · ${reply.createdAtLabel}',
                          style: context.text.metadata.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Mv2Spacing.x2),
                    if (contentHtml != null)
                      _body(
                        Mv2RichText(
                          html: contentHtml,
                          baseStyle: bodyStyle,
                          onMentionTap: onMentionTap,
                          onFloorRefTap: onFloorRefTap,
                        ),
                      )
                    else
                      _body(Text(reply.content, style: bodyStyle)),
                    const SizedBox(height: Mv2Spacing.x2),
                    Row(
                      children: <Widget>[
                        // V2EX has **no reply like**: the reply's 👍/❤️ number is
                        // just its 感谢数 and there is no endpoint to toggle it,
                        // so it is not rendered as an action. 感谢 is the only
                        // reply feedback, and it is one-way ("感谢已发送").
                        _ReplyAction(
                          icon: thanked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          label: '感谢',
                          highlighted: thanked,
                          onTap: onThank,
                        ),
                        if (onQuote != null) ...<Widget>[
                          const SizedBox(width: Mv2Spacing.x5),
                          _ReplyAction(
                            icon: Icons.format_quote_rounded,
                            label: '引用',
                            onTap: onQuote,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyAction extends StatelessWidget {
  const _ReplyAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = highlighted ? colors.accent : colors.textTertiary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 4),
          Text(label, style: context.text.metadata.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// `54 条回复` + a static `默认排序` selector.
class _ReplySectionHeader extends StatelessWidget {
  const _ReplySectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: <Widget>[
        Text(
          label,
          style: context.text.sectionTitle.copyWith(color: colors.textPrimary),
        ),
        const Spacer(),
        Text(
          '默认排序',
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(width: Mv2Spacing.x1),
        Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 16,
          color: colors.textSecondary,
        ),
      ],
    );
  }
}

/// Placeholder pagination affordance; paging lands in phase 2B.
class _NextPageButton extends StatelessWidget {
  const _NextPageButton({required this.onTap, this.label = '下一页'});

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

/// Article-shaped skeleton shown while the detail request is in flight.
class _TopicArticleSkeleton extends StatelessWidget {
  const _TopicArticleSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x3,
        Mv2Spacing.pageNarrow,
        Mv2PageScaffold.bottomContentInset(context) + FloatingReplyBar.height,
      ),
      children: const <Widget>[
        Mv2SkeletonBox(width: 56, height: 20),
        SizedBox(height: Mv2Spacing.x3),
        Mv2SkeletonBox(width: double.infinity, height: 24),
        SizedBox(height: Mv2Spacing.x2),
        Mv2SkeletonBox(width: 200, height: 24),
        SizedBox(height: Mv2Spacing.x4),
        Row(
          children: <Widget>[
            Mv2SkeletonBox(width: 22, height: 22, radius: Mv2Radius.pill),
            SizedBox(width: Mv2Spacing.x2),
            Mv2SkeletonBox(width: 120, height: 12),
          ],
        ),
        SizedBox(height: Mv2Spacing.x5),
        Mv2SkeletonBox(width: double.infinity, height: 15),
        SizedBox(height: Mv2Spacing.x2),
        Mv2SkeletonBox(width: double.infinity, height: 15),
        SizedBox(height: Mv2Spacing.x2),
        Mv2SkeletonBox(width: 240, height: 15),
        SizedBox(height: Mv2Spacing.x5),
        Mv2SkeletonBox(width: double.infinity, height: 15),
        SizedBox(height: Mv2Spacing.x2),
        Mv2SkeletonBox(width: double.infinity, height: 15),
        SizedBox(height: Mv2Spacing.x2),
        Mv2SkeletonBox(width: 180, height: 15),
        SizedBox(height: Mv2Spacing.x5),
        Mv2SkeletonBox(
          width: double.infinity,
          height: 72,
          radius: Mv2Radius.allMd,
        ),
        SizedBox(height: Mv2Spacing.x4),
        Mv2SkeletonBox(
          width: double.infinity,
          height: 52,
          radius: Mv2Radius.allMd,
        ),
        SizedBox(height: Mv2Spacing.x6),
        Mv2SkeletonBox(width: 96, height: 20),
        SizedBox(height: Mv2Spacing.x4),
        Mv2SkeletonBox(
          width: double.infinity,
          height: 88,
          radius: Mv2Radius.allMd,
        ),
        SizedBox(height: Mv2Spacing.x3),
        Mv2SkeletonBox(
          width: double.infinity,
          height: 88,
          radius: Mv2Radius.allMd,
        ),
      ],
    );
  }
}

/// `OP` / `PRO` chip straight from V2EX's own `div.badge` markup.
class _ReplyBadge extends StatelessWidget {
  const _ReplyBadge({required this.label});

  final String label;

  bool get _isOwner => label.toUpperCase() == 'OP';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _isOwner ? colors.accentSoft : colors.divider,
        borderRadius: Mv2Radius.allXs,
      ),
      child: Text(
        // V2EX's own label is `OP` and that is the established convention —
        // do not translate it to 楼主.
        label,
        style: context.text.badge.copyWith(
          color: _isOwner ? colors.accent : colors.textSecondary,
        ),
      ),
    );
  }
}
