import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/session_once.dart';
import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/telemetry/mv2_analytics.dart';
import '../../../core/telemetry/mv2_telemetry.dart';
import '../../../core/text/base64_text.dart';
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
import '../../../ui/mv2_haptics.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../auth/application/auth_controller.dart';
import '../../settings/application/settings_controller.dart';
import '../../topic/application/topic_providers.dart';
import '../application/draft_store.dart';
import 'composer_emoji_panel.dart';
import 'composer_image_button.dart';

/// Reply composer (`designs/03-reply-composer.png`).
///
/// Compact reply context, a flexible editor, and a keyboard-adjacent toolbar.
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

  /// Context expansion is controlled by the reader, never by typing.
  bool _quoteExpanded = false;
  Timer? _savedTimer;
  String _draftStatus = '';
  int _draftRevision = 0;

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
    _savedTimer?.cancel();
    // Flush text typed in the last debounce window; a submitted reply must not
    // be resurrected as a draft.
    final pending = _controller.text;
    if (!_submitted) {
      unawaited(() async {
        try {
          await _draftStore.write(_draftKey, pending);
        } catch (error, stack) {
          Mv2Telemetry.recordNonFatal(
            error,
            stack,
            reason: 'draft.write $_draftKey',
          );
        }
      }());
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
    final String? saved;
    try {
      saved = await _draftStore.read(_draftKey);
    } catch (error, stack) {
      Mv2Telemetry.recordNonFatal(
        error,
        stack,
        reason: 'draft.read $_draftKey',
      );
      if (mounted) setState(() => _draftStatus = '草稿读取失败');
      return;
    }
    if (!mounted) return;
    if (saved != null && saved.isNotEmpty) {
      if (_controller.text.isEmpty) {
        _controller.value = TextEditingValue(
          text: saved,
          selection: TextSelection.collapsed(offset: saved.length),
        );
      }
      Mv2Analytics.logDraftAction(composer: 'reply', action: 'restored');
      return;
    }
    // Fresh composer: seed the `@user #floor` reference only when there is no
    // draft, to avoid splicing it into text the user already wrote.
    final initial = widget.initialText;
    if (initial != null && initial.isNotEmpty && _controller.text.isEmpty) {
      _controller.text = initial;
    }
  }

  void _onTextChanged() {
    // Rebuilds the 发送 enabled state and restarts the debounce.
    setState(() {});
    _savedTimer?.cancel();
    _draftStatus = '';
    final revision = ++_draftRevision;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _draftStore.write(_draftKey, _controller.text);
        if (!mounted || _submitted || revision != _draftRevision) return;
        setState(
          () => _draftStatus = _controller.text.trim().isEmpty ? '' : '已保存',
        );
        _savedTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _draftStatus = '');
        });
      } catch (error, stack) {
        Mv2Telemetry.recordNonFatal(
          error,
          stack,
          reason: 'draft.write $_draftKey',
        );
        if (mounted && revision == _draftRevision) {
          setState(() => _draftStatus = '草稿保存失败');
        }
      }
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

  /// 把选中的文字原位编码为 Base64（联系方式防爬虫，V2EX Polish 的
  /// 「文字转 Base64」同款）。没选中时只提示，绝不整体编码——那是
  /// 不可逆感很强的破坏性操作。
  void _encodeBase64() {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先选中要编码的文字，再点 Base64')));
      return;
    }
    _controller.value = Base64Text.encodeSelection(_controller.value);
    Mv2Analytics.logBase64Tool(action: 'encode');
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
        // Confirm the write like 发布主题 does: capture the root messenger
        // before the pop, close the sheet, then toast — a SnackBar shown on a
        // scaffold being disposed in the same frame crashed before (`docs/13`
        // Phase 3), the root messenger outlives the route.
        Mv2Haptics.success(ref.read(settingsProvider).hapticsEnabled);
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        mv2ShowSuccess(messenger, '回复已发布');
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

  /// Leaves the sheet before opening the login route: `/login` must sit on the
  /// root navigator, not on the composer's modal route.
  void _goLogin() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/login');
  }

  /// A signed-in composer that still has no `once` usually scraped an anonymous
  /// topic page. Let the banner retry the scrape instead of forcing a sign-out.
  Future<void> _retryOnce() async {
    _onceAttempted = false;
    await _refreshOnce();
    if (mounted) setState(() {});
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
    final auth = ref.watch(authControllerProvider);
    final signedIn = auth.value?.isSignedIn ?? false;
    // A detail cached before the sign-in has no `once`; recover on the spot once
    // it has settled (see `session_cache_refresh.dart` for the cache fix).
    if (once == null && signedIn && detail.hasValue && !detail.isLoading) {
      _scheduleEnsureOnce();
    }
    final canReply = once != null && once.isNotEmpty;
    final canSend = canReply && !_sending && _controller.text.trim().isNotEmpty;

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(
        title: '回复',
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
      child: Column(
        children: <Widget>[
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.22,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: topic != null
                    ? _ReplyContext(
                        topic: topic,
                        reply: quotedReply,
                        expanded: _quoteExpanded,
                        onToggle: () =>
                            setState(() => _quoteExpanded = !_quoteExpanded),
                      )
                    : detail.hasError
                    ? Mv2StateView(
                        kind: Mv2StateKind.error,
                        compact: true,
                        description: mv2DescribeError(detail.error!),
                        actionLabel: '重试',
                        onAction: () => ref.invalidate(
                          topicDetailProvider(TopicDetailArgs(widget.topicId)),
                        ),
                      )
                    : const LinearProgressIndicator(minHeight: 1),
              ),
            ),
          ),
          Divider(height: 1, color: colors.divider),
          if (!canReply && !_sending)
            _ReplyPermissionBanner(
              signedIn: signedIn,
              loading: detail.isLoading || auth.isLoading,
              onLogin: _goLogin,
              onRetry: () => unawaited(_retryOnce()),
            ),
          if (_errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _ComposerErrorBanner(errors: _errors),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                cursorColor: colors.accent,
                style: context.text.body.copyWith(color: colors.textPrimary),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: '写下你的回复…',
                  hintStyle: context.text.body.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ),
          ),
          if (_emojiOpen)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.28,
              ),
              child: SingleChildScrollView(
                child: ComposerEmojiPanel(onSelect: _insertAtCursor),
              ),
            ),
          SafeArea(
            top: false,
            child: _ComposerToolbar(
              onInsertImage: _insertAtCursor,
              emojiOpen: _emojiOpen,
              onToggleEmoji: _toggleEmoji,
              onBase64: _encodeBase64,
              draftStatus: _draftStatus,
            ),
          ),
        ],
      ),
    );
  }
}

/// Explains why 发送 is unavailable instead of leaving a dead grey button.
///
/// The floating reply bar and deep links can open the composer before the
/// session/scraped `once` is ready; this banner turns that into an actionable
/// state (sign in or retry) rather than a silent no-op.
class _ReplyPermissionBanner extends StatelessWidget {
  const _ReplyPermissionBanner({
    required this.signedIn,
    required this.loading,
    required this.onLogin,
    required this.onRetry,
  });

  final bool signedIn;
  final bool loading;
  final VoidCallback onLogin;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = loading
        ? '正在获取回复权限…'
        : signedIn
        ? '回复权限已失效，请重试或重新登录。'
        : '登录 V2EX 账号后才能回复。';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: Mv2Radius.allMd,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: colors.textSecondary,
          ),
          const SizedBox(width: Mv2Spacing.x2),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Mv2Spacing.x2),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...<Widget>[
            if (signedIn)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: colors.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Mv2Spacing.x2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('重试'),
              ),
            TextButton(
              onPressed: onLogin,
              style: TextButton.styleFrom(
                foregroundColor: colors.accent,
                padding: const EdgeInsets.symmetric(horizontal: Mv2Spacing.x2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(signedIn ? '重新登录' : '去登录'),
            ),
          ],
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

/// Compact context stays stable while typing; expansion is always explicit.
class _ReplyContext extends StatelessWidget {
  const _ReplyContext({
    required this.topic,
    required this.reply,
    required this.expanded,
    required this.onToggle,
  });
  final V2Topic topic;
  final V2Reply? reply;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final target = reply;
    final excerpt = target?.content.trim() ?? topic.excerpt?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    target == null
                        ? '回复主题 · ${topic.title}'
                        : '回复 @${target.author.username}',
                    maxLines: expanded ? null : 1,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: context.text.bodySmall.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
                if (target != null)
                  Text(
                    ' · #${target.floor}',
                    style: context.text.metadata.copyWith(
                      color: context.colors.textTertiary,
                    ),
                  ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: context.colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (excerpt.isNotEmpty && (target != null || expanded))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              excerpt,
              maxLines: expanded ? null : 2,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: context.text.bodySmall.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        if (expanded && excerpt.isEmpty && target == null)
          Text(
            '收起编辑器可查看主题全文',
            style: context.text.metadata.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
      ],
    );
  }
}

class _ComposerToolbar extends StatelessWidget {
  const _ComposerToolbar({
    required this.onInsertImage,
    required this.emojiOpen,
    required this.onToggleEmoji,
    required this.onBase64,
    required this.draftStatus,
  });
  final ValueChanged<String> onInsertImage;
  final bool emojiOpen;
  final VoidCallback onToggleEmoji;
  final VoidCallback onBase64;
  final String draftStatus;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: context.colors.divider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              ComposerImageButton(onInsert: onInsertImage, markdown: false),
              Mv2ToolbarButton(
                label: '表情',
                icon: Icons.sentiment_satisfied_alt_outlined,
                active: emojiOpen,
                onPressed: onToggleEmoji,
              ),
              PopupMenuButton<String>(
                tooltip: '更多工具',
                icon: Icon(
                  Icons.more_horiz,
                  color: context.colors.textSecondary,
                ),
                onSelected: (value) {
                  if (value == 'base64') onBase64();
                  if (value == 'markdown') {
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('回复格式'),
                        content: const Text(
                          '回复使用纯文本，网址会自动识别。图片地址单独放一行即可展示图片，无需添加 Markdown 图片标记。\n\nBase64 编码：先在正文中选中文字，再从更多工具中选择编码。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('知道了'),
                          ),
                        ],
                      ),
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'markdown', child: Text('回复格式帮助')),
                  PopupMenuItem(
                    value: 'base64',
                    child: Text('将选中文字编码为 Base64'),
                  ),
                ],
              ),
              Expanded(
                child: Text(
                  draftStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: context.text.metadata.copyWith(
                    color: draftStatus.contains('失败')
                        ? context.colors.danger
                        : context.colors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ],
    );
  }
}
