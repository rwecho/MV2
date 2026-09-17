import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/session_once.dart';
import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/telemetry/mv2_analytics.dart';
import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/emoji/mv2_emoji_library.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/topic_detail.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/primitives/mv2_avatar.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../../ui/primitives/mv2_chips.dart';
import '../../auth/application/auth_controller.dart';
import '../../topic/application/topic_providers.dart';
import '../application/draft_store.dart';
import 'composer_emoji_panel.dart';
import 'composer_image_button.dart';

/// Reply composer (`designs/03-reply-composer.png`).
///
/// The quoted topic stays pinned in the scroll body while the footer is fixed
/// above the keyboard inset.
class ReplyComposerPage extends ConsumerStatefulWidget {
  const ReplyComposerPage({
    super.key,
    required this.topicId,
    this.floor,
    this.quotedReply,
    this.initialText,
  });

  final int topicId;
  final int? floor;

  /// The reply the user tapped 引用 on. Passed through the route `extra` so a
  /// quote from a later reply page still renders; falls back to a lookup by
  /// [floor] in the cached first page.
  final V2Reply? quotedReply;

  /// Seeds an empty editor, e.g. `#5 ` when the quoted author has several
  /// replies and a bare `@user` would be ambiguous (V2EX Polish does the same).
  final String? initialText;

  @override
  ConsumerState<ReplyComposerPage> createState() => _ReplyComposerPageState();
}

class _ReplyComposerPageState extends ConsumerState<ReplyComposerPage> {
  late final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final DraftStore _draftStore;
  Timer? _draftTimer;
  bool _sending = false;

  /// A topic page fetched while signed out carries no `once`, and the cached
  /// detail may still be the anonymous copy right after a sign-in. Attempt to
  /// self-heal the token once per composer session so 发送 can light up without
  /// the user re-opening the page.
  bool _onceAttempted = false;

  /// Emoji picker pinned above the toolbar.
  bool _emojiOpen = false;

  /// Set once the reply is accepted; stops [dispose] from re-saving the draft
  /// that the successful submit just cleared.
  bool _submitted = false;

  /// Parsed `div.problem li` messages from the last rejected submit.
  List<String> _errors = const <String>[];

  String get _draftKey => DraftStore.topicKey(widget.topicId);

  @override
  void initState() {
    super.initState();
    _draftStore = ref.read(draftStoreProvider);
    _controller.addListener(_onTextChanged);
    // Typing means the user wants the keyboard, not the emoji panel.
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _emojiOpen) {
        setState(() => _emojiOpen = false);
      }
    });
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    // Flush text typed in the last debounce window; a submitted reply must not
    // be resurrected as a draft.
    final pending = _controller.text;
    if (!_submitted && pending.trim().isNotEmpty) {
      unawaited(_draftStore.write(_draftKey, pending));
    }
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleEmoji() {
    final open = !_emojiOpen;
    setState(() => _emojiOpen = open);
    if (open) FocusScope.of(context).unfocus();
  }

  Future<void> _restoreDraft() async {
    final saved = await _draftStore.read(_draftKey);
    if (!mounted) return;
    if (saved != null && saved.isNotEmpty) {
      if (_controller.text.isEmpty) _controller.text = saved;
      Mv2Analytics.logDraftAction(composer: 'reply', action: 'restored');
      return;
    }
    // Fresh composer: seed the floor marker only when there is no draft to
    // avoid splicing it into text the user already wrote.
    final initial = widget.initialText;
    if (initial != null && initial.isNotEmpty && _controller.text.isEmpty) {
      _controller.text = initial;
    }
  }

  void _onTextChanged() {
    // Rebuilds the 发送 enabled state and restarts the debounce.
    setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), () {
      final text = _controller.text;
      if (text.trim().isEmpty) return;
      unawaited(_draftStore.write(_draftKey, text));
      Mv2Analytics.logDraftAction(composer: 'reply', action: 'saved');
    });
  }

  /// Inserts [snippet] at the caret (replacing any selection) and leaves the
  /// caret after it, so an uploaded image lands where the user was typing.
  void _insertAtCursor(String snippet) {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    _controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, snippet),
      selection: TextSelection.collapsed(offset: start + snippet.length),
    );
  }

  /// Resolves the reply being quoted, so the quote block always mirrors the
  /// comment the user tapped 引用 on.
  V2Reply? _quotedReply(V2TopicDetail? detail) {
    final passed = widget.quotedReply;
    if (passed != null) return passed;
    final floor = widget.floor;
    if (floor == null || detail == null) return null;
    for (final reply in detail.replies) {
      if (reply.floor == floor) return reply;
    }
    return null;
  }

  Future<void> _send(String once) async {
    if (_sending) return;
    // `[doge]`-style tokens become hosted image URLs only in the submitted
    // body; the editor and the saved draft keep the readable token.
    final content = Mv2EmojiLibrary.expandForSubmit(_controller.text).trim();
    if (content.isEmpty) return;
    setState(() {
      _sending = true;
      _errors = const <String>[];
    });
    try {
      var token = once;
      var result = await ref
          .read(v2exApiProvider)
          .replyToTopic(widget.topicId, content, token);
      // `once` rotates on every page render; a CSRF rejection means our copy is
      // stale, so re-scrape the topic page and retry exactly once.
      if (result.looksLikeOnceFailure) {
        final fresh = await _refreshOnce();
        if (fresh != null && fresh != token) {
          token = fresh;
          result = await ref
              .read(v2exApiProvider)
              .replyToTopic(widget.topicId, content, token);
        }
      }
      if (!mounted) return;
      if (result.success) {
        _submitted = true;
        _draftTimer?.cancel();
        await _draftStore.clear(_draftKey);
        Mv2Analytics.logDraftAction(composer: 'reply', action: 'cleared');
        Mv2Analytics.logReplySubmit(
          topicId: widget.topicId,
          hasQuote: widget.quotedReply != null || widget.floor != null,
          contentLength: content.length,
          result: 'success',
        );
        if (!mounted) return;
        // Force the detail provider to refetch so the new reply is visible.
        ref.invalidate(topicDetailProvider(TopicDetailArgs(widget.topicId)));
        // Closes the modal sheet (this page is no longer a routed page).
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _sending = false;
        _errors = result.errors.isEmpty
            ? const <String>['发送失败，请稍后重试。']
            : result.errors;
      });
      Mv2Analytics.logReplySubmit(
        topicId: widget.topicId,
        hasQuote: widget.quotedReply != null || widget.floor != null,
        contentLength: content.length,
        result: 'failed',
      );
    } on AuthFailure catch (failure) {
      // 401/403 mid-session: sign the stale session out before surfacing.
      await ref.read(authControllerProvider.notifier).handleAuthFailure();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errors = <String>[failure.message];
      });
      Mv2Analytics.logReplySubmit(
        topicId: widget.topicId,
        hasQuote: widget.quotedReply != null || widget.floor != null,
        contentLength: content.length,
        result: 'auth_required',
      );
    } on Failure catch (failure) {
      // Includes RateLimitFailure, whose message must be shown verbatim.
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errors = <String>[failure.message];
      });
      Mv2Analytics.logReplySubmit(
        topicId: widget.topicId,
        hasQuote: widget.quotedReply != null || widget.floor != null,
        contentLength: content.length,
        result: failure is RateLimitFailure ? 'rate_limited' : 'failed',
      );
    }
  }

  /// Re-fetches the topic page for a token issued *now* (a page render rotates
  /// the session's `once`).
  Future<String?> _refreshOnce() async {
    try {
      final detail = await ref
          .read(v2exApiProvider)
          .topicDetail(widget.topicId);
      final token = detail.once;
      if (token == null || token.isEmpty) return null;
      ref.read(sessionOnceProvider.notifier).update(token);
      return token;
    } catch (_) {
      // Best effort: on failure the caller keeps the original rejection.
      return null;
    }
  }

  /// Fetches a token in the background when the composer has none but the
  /// session is signed in — the cached topic detail was scraped anonymously, so
  /// it has no `once`. Runs at most once per composer session; a later rebuild
  /// that still lacks a token just leaves 发送 disabled (e.g. a locked account).
  void _scheduleEnsureOnce() {
    if (_onceAttempted) return;
    _onceAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshOnce());
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Watching the detail provider makes the 发送 button light up as soon as
    // the topic (and its `once` token) has loaded.
    final detail = ref.watch(
      topicDetailProvider(TopicDetailArgs(widget.topicId)),
    );
    final topic = detail.value?.topic;
    final quotedReply = _quotedReply(detail.value);
    // Prefer the session's newest token: a 感谢 on the topic page rotates it,
    // and the composer must not post with the stale scraped value.
    final once = ref.watch(sessionOnceProvider) ?? detail.value?.once;
    // A detail cached before the sign-in has no `once`; recover on the spot once
    // it has settled (see `session_cache_refresh.dart` for the cache fix).
    if (once == null &&
        ref.watch(isSignedInProvider) &&
        detail.hasValue &&
        !detail.isLoading) {
      _scheduleEnsureOnce();
    }
    final canSend =
        once != null &&
        once.isNotEmpty &&
        !_sending &&
        _controller.text.trim().isNotEmpty;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(
        title: '回复主题',
        leadingIcon: Icons.close_rounded,
        onBack: () => Navigator.of(context).maybePop(),
        actions: <Widget>[
          Mv2TextButton(
            label: '发送',
            loading: _sending,
            enabled: canSend,
            onPressed: canSend ? () => unawaited(_send(once)) : null,
          ),
        ],
      ),
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_emojiOpen) ComposerEmojiPanel(onSelect: _insertAtCursor),
          _ComposerToolbar(
            onInsertImage: _insertAtCursor,
            emojiOpen: _emojiOpen,
            onToggleEmoji: _toggleEmoji,
          ),
          _ComposerFooter(draftSaved: _controller.text.trim().isNotEmpty),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          Mv2Spacing.pageNarrow,
          Mv2Spacing.x3,
          Mv2Spacing.pageNarrow,
          // Clears the pinned toolbar + footer overlay.
          Mv2Spacing.x8 + 96 + bottomInset,
        ),
        children: <Widget>[
          // 引用卡：loaded → real card; loading → placeholder; failure →
          // the standard error state with retry, never a stand-in topic.
          if (topic != null)
            _QuotedTopicCard(topic: topic)
          else if (detail.hasError)
            Mv2StateView(
              kind: Mv2StateKind.error,
              compact: true,
              description: mv2DescribeError(detail.error!),
              actionLabel: '重试',
              onAction: () => ref.invalidate(
                topicDetailProvider(TopicDetailArgs(widget.topicId)),
              ),
            )
          else
            const _QuotedTopicSkeleton(),
          if (quotedReply != null) ...<Widget>[
            const SizedBox(height: Mv2Spacing.x3),
            _QuoteBlock(reply: quotedReply),
          ],
          const SizedBox(height: Mv2Spacing.x3),
          Mv2Surface(
            padding: const EdgeInsets.all(Mv2Spacing.x4),
            shadowed: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_errors.isNotEmpty) ...<Widget>[
                  _ComposerErrorBanner(errors: _errors),
                  const SizedBox(height: Mv2Spacing.x3),
                ],
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  // The keyboard is the point of the sheet: open it immediately.
                  autofocus: true,
                  maxLines: null,
                  minLines: 10,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  cursorColor: colors.accent,
                  style: context.text.body.copyWith(color: colors.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '写下你的回复...',
                    hintStyle: context.text.body.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline submit errors, rendered in the danger token so a rejected reply is
/// never a silent failure.
class _ComposerErrorBanner extends StatelessWidget {
  const _ComposerErrorBanner({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Mv2Spacing.x3),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.08),
        borderRadius: Mv2Radius.allMd,
        border: Border.all(color: colors.danger.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final error in errors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x1 / 2),
              child: Text(
                error,
                style: context.text.bodySmall.copyWith(color: colors.danger),
              ),
            ),
        ],
      ),
    );
  }
}

/// The topic being replied to, quoted at the top of the composer.
/// Loading placeholder matching [_QuotedTopicCard] metrics.
class _QuotedTopicSkeleton extends StatelessWidget {
  const _QuotedTopicSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Mv2Surface(
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      shadowed: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 72,
            height: 16,
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: Mv2Radius.allSm,
            ),
          ),
          const SizedBox(height: Mv2Spacing.x2),
          Container(
            width: double.infinity,
            height: 18,
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: Mv2Radius.allSm,
            ),
          ),
          const SizedBox(height: Mv2Spacing.x2),
          FractionallySizedBox(
            widthFactor: 0.6,
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: Mv2Radius.allSm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotedTopicCard extends StatelessWidget {
  const _QuotedTopicCard({required this.topic});

  final V2Topic topic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final excerpt = topic.excerpt;

    return Mv2Surface(
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      shadowed: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Mv2NodeBadge(node: topic.node),
          const SizedBox(height: Mv2Spacing.x2),
          Text(
            topic.title,
            style: context.text.topicTitle.copyWith(color: colors.textPrimary),
          ),
          if (excerpt != null) ...<Widget>[
            const SizedBox(height: Mv2Spacing.x2),
            Text(
              excerpt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: Mv2Spacing.x3),
          Row(
            children: <Widget>[
              Mv2Avatar(user: topic.author, size: 20),
              const SizedBox(width: Mv2Spacing.x2),
              Text(
                '${topic.author.username} · ${topic.createdAtLabel}',
                style: context.text.metadata.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.mode_comment_outlined,
                size: 14,
                color: colors.textTertiary,
              ),
              const SizedBox(width: Mv2Spacing.x1),
              Text(
                '${topic.replyCount}',
                style: context.text.metadata.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Accent-soft quote of the referenced floor (`floor` query parameter).
class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.reply});

  /// The reply the composer is quoting, resolved from the topic detail.
  final V2Reply reply;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = reply.content.trim();

    return ClipRRect(
      borderRadius: Mv2Radius.allMd,
      child: ColoredBox(
        color: colors.accentSoft,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: 3, color: colors.accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(Mv2Spacing.x3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '回复 @${reply.author.username}',
                        style: context.text.bodyStrong.copyWith(
                          color: colors.accent,
                        ),
                      ),
                      if (content.isNotEmpty) ...<Widget>[
                        const SizedBox(height: Mv2Spacing.x2),
                        Text(
                          content,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinned toolbar directly above the footer (`designs/03-reply-composer.png`).
///
/// Image + emoji only: V2EX is Markdown by default, and the old 引用/预览/
/// Markdown buttons were stubs. 表情 opens V2EX Polish's emoji library.
class _ComposerToolbar extends StatelessWidget {
  const _ComposerToolbar({
    required this.onInsertImage,
    required this.emojiOpen,
    required this.onToggleEmoji,
  });

  final ValueChanged<String> onInsertImage;
  final bool emojiOpen;
  final VoidCallback onToggleEmoji;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ColoredBox(
      color: colors.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(height: 1, color: colors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x1),
            child: Row(
              children: <Widget>[
                ComposerImageButton(onInsert: onInsertImage),
                Mv2ToolbarButton(
                  label: '表情',
                  icon: Icons.sentiment_satisfied_alt_outlined,
                  active: emojiOpen,
                  onPressed: onToggleEmoji,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned footer: Markdown hint on the left, real draft status on the right.
class _ComposerFooter extends StatelessWidget {
  const _ComposerFooter({required this.draftSaved});

  /// True while the editor holds text that is persisted (or about to be).
  final bool draftSaved;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusColor = draftSaved ? colors.success : colors.textTertiary;

    return ColoredBox(
      color: colors.background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Mv2Spacing.pageNarrow,
            Mv2Spacing.x2,
            Mv2Spacing.pageNarrow,
            Mv2Spacing.x2,
          ),
          child: Row(
            children: <Widget>[
              Text(
                '支持 Markdown',
                style: context.text.metadata.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const Spacer(),
              Icon(
                draftSaved ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 15,
                color: statusColor,
              ),
              const SizedBox(width: Mv2Spacing.x1),
              Text(
                draftSaved ? '草稿已保存' : '暂无草稿',
                style: context.text.metadata.copyWith(color: statusColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
