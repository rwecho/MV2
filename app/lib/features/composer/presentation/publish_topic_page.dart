import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/format/mv2_markdown.dart';
import '../../../shared/models/models.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_rich_text.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../../ui/utils/mv2_breakpoints.dart';
import '../../shell/application/tablet_topic_pane.dart';
import '../application/publish_providers.dart';
import 'composer_emoji_panel.dart';
import 'composer_image_button.dart';

/// Publish Topic (`docs/06` → Publish Topic).
///
/// There is no mockup for this page yet (`docs/13` §6), so the structure
/// deliberately inherits the Reply Composer: pinned header action, scrolling
/// editor, pinned toolbar + draft footer, node/title/content before submit.
class PublishTopicPage extends ConsumerStatefulWidget {
  const PublishTopicPage({super.key, this.initialNode});

  /// Node slug from `/publish?node=…`, preselected when the composer opens.
  final String? initialNode;

  @override
  ConsumerState<PublishTopicPage> createState() => _PublishTopicPageState();
}

class _PublishTopicPageState extends ConsumerState<PublishTopicPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final FocusNode _contentFocus = FocusNode();

  /// Emoji picker pinned above the toolbar.
  bool _emojiOpen = false;

  @override
  void initState() {
    super.initState();
    // Typing means the user wants the keyboard, not the emoji panel.
    _contentFocus.addListener(() {
      if (_contentFocus.hasFocus && _emojiOpen) {
        setState(() => _emojiOpen = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    await ref
        .read(publishProvider.notifier)
        .load(initialNode: widget.initialNode);
    if (!mounted) return;
    final state = ref.read(publishProvider);
    _title.text = state.title;
    _content.text = state.content;
    setState(() {});
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _toggleEmoji() {
    final open = !_emojiOpen;
    setState(() => _emojiOpen = open);
    if (open) FocusScope.of(context).unfocus();
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final published = await ref.read(publishProvider.notifier).submit();
    if (!published || !mounted) return;

    final topicId = ref.read(publishProvider).publishedTopicId;
    // Decide the post-publish destination before popping: on tablets the topic
    // goes into the shell's detail pane (the provider lives in the root
    // container, so the write survives the pop), on phones it is pushed after.
    final openInPane = topicId != null && mv2IsTwoPane(context);
    if (topicId != null) {
      // 发布成功后自动打开新主题;composer 不是路由,这里是 topic_open 的
      // 'publish' 来源唯一入口。
      Mv2Analytics.logTopicOpen(
        topicId: topicId,
        source: 'publish',
        layout: openInPane ? 'tablet' : 'phone',
      );
    }
    if (openInPane) {
      ProviderScope.containerOf(context, listen: false)
          .read(tabletTopicPaneProvider.notifier)
          .open(topicId, null);
    }
    // Pop before showing the confirmation: a SnackBar attached to a scaffold
    // that is being disposed in the same frame caused a Hero-tag crash on the
    // login page (`docs/13` Phase 3). The root messenger outlives the route.
    router.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('主题已发布')));
    if (topicId != null && !openInPane) router.push('/topic/$topicId');
  }

  Future<void> _pickNode() async {
    final choice = await showModalBottomSheet<({String slug, String title})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Mv2Spacing.x5),
        ),
      ),
      builder: (context) =>
          _NodePickerSheet(selected: ref.read(publishProvider).nodeSlug),
    );
    if (choice == null || !mounted) return;
    ref.read(publishProvider.notifier).selectNode(choice.slug, choice.title);
  }

  void _wrapSelection(String before, String after) {
    final value = _content.value;
    final text = value.text;
    final selection = value.selection;
    if (!selection.isValid) {
      _content.text = '$text$before$after';
    } else {
      final selected = selection.textInside(text);
      final replacement = '$before$selected$after';
      _content.value = value.copyWith(
        text: text.replaceRange(selection.start, selection.end, replacement),
        selection: TextSelection.collapsed(
          offset: selection.start + replacement.length,
        ),
        composing: TextRange.empty,
      );
    }
    ref.read(publishProvider.notifier).setContent(_content.text);
  }

  void _togglePreview() => ref.read(publishProvider.notifier).togglePreview();

  /// Inserts [snippet] (an uploaded image) at the body caret and syncs the draft.
  void _insertIntoContent(String snippet) {
    final value = _content.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    _content.value = value.copyWith(
      text: value.text.replaceRange(start, end, snippet),
      selection: TextSelection.collapsed(offset: start + snippet.length),
      composing: TextRange.empty,
    );
    ref.read(publishProvider.notifier).setContent(_content.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(publishProvider);
    final showComposer = state.form != null && state.failure == null;

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(
        title: '发布主题',
        leadingIcon: Icons.close_rounded,
        onBack: () => Navigator.of(context).maybePop(),
        actions: <Widget>[
          Mv2TextButton(
            label: '发布',
            loading: state.submitting,
            enabled: state.canSubmit,
            onPressed: _submit,
          ),
        ],
      ),
      bottomBar: showComposer
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_emojiOpen)
                  ComposerEmojiPanel(onSelect: _insertIntoContent),
                _PublishToolbar(
                  preview: state.preview,
                  onTogglePreview: _togglePreview,
                  onInsertImage: _insertIntoContent,
                  emojiOpen: _emojiOpen,
                  onToggleEmoji: _toggleEmoji,
                  onBold: () => _wrapSelection('**', '**'),
                  onCode: () => _wrapSelection('`', '`'),
                  onLink: () => _wrapSelection('[', '](https://)'),
                ),
                _PublishFooter(saved: state.draftSaved),
              ],
            )
          : null,
      child: _buildBody(state),
    );
  }

  Widget _buildBody(PublishState state) {
    if (state.loading && state.form == null) {
      return const _PublishSkeleton();
    }
    if (state.signedOut) {
      return Mv2StateView(
        kind: Mv2StateKind.empty,
        title: '登录后即可发布主题',
        description: 'V2EX 要求登录后才能在节点下创建新主题。',
        actionLabel: '去登录',
        onAction: () => context.push('/login'),
      );
    }
    if (state.failure != null) {
      return Mv2StateView(
        kind: Mv2StateKind.error,
        title: '无法打开发布页',
        description: state.failure!.message,
        actionLabel: '重试',
        onAction: () => ref.read(publishProvider.notifier).retry(),
      );
    }

    final colors = context.colors;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x3,
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x8 + 96 + bottomInset,
      ),
      children: <Widget>[
        _NodeSelector(
          slug: state.nodeSlug,
          title: state.nodeTitle,
          onTap: _pickNode,
        ),
        if (state.problems.isNotEmpty) ...<Widget>[
          const SizedBox(height: Mv2Spacing.x3),
          _ProblemBlock(problems: state.problems),
        ],
        const SizedBox(height: Mv2Spacing.x3),
        Mv2Surface(
          padding: const EdgeInsets.all(Mv2Spacing.x4),
          shadowed: false,
          child: TextField(
            controller: _title,
            // The keyboard is the point of the sheet: open it immediately.
            autofocus: true,
            maxLines: 2,
            minLines: 1,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            onChanged: ref.read(publishProvider.notifier).setTitle,
            cursorColor: colors.accent,
            style: context.text.topicTitle.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              counterText: '',
              hintText: '填写标题',
              hintStyle: context.text.topicTitle.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
        ),
        const SizedBox(height: Mv2Spacing.x3),
        Mv2Surface(
          padding: const EdgeInsets.all(Mv2Spacing.x4),
          shadowed: false,
          child: state.preview
              ? _PreviewPane(markdown: state.content)
              : TextField(
                  controller: _content,
                  focusNode: _contentFocus,
                  maxLines: null,
                  minLines: 10,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: ref.read(publishProvider.notifier).setContent,
                  cursorColor: colors.accent,
                  style: context.text.body.copyWith(color: colors.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '写下正文，支持 Markdown...',
                    hintStyle: context.text.body.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Tappable node row; opens [_NodePickerSheet].
class _NodeSelector extends StatelessWidget {
  const _NodeSelector({
    required this.slug,
    required this.title,
    required this.onTap,
  });

  final String? slug;
  final String? title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = slug != null;

    return Mv2Surface(
      padding: const EdgeInsets.symmetric(
        horizontal: Mv2Spacing.x4,
        vertical: Mv2Spacing.x3,
      ),
      shadowed: false,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(
            Icons.grid_view_rounded,
            size: 18,
            color: selected ? colors.accent : colors.textTertiary,
          ),
          const SizedBox(width: Mv2Spacing.x3),
          Text(
            selected ? (title ?? slug!) : '选择节点',
            style: context.text.bodyStrong.copyWith(
              color: selected ? colors.textPrimary : colors.textTertiary,
            ),
          ),
          if (selected && title != null) ...<Widget>[
            const SizedBox(width: Mv2Spacing.x2),
            Text(
              '/go/$slug',
              style: context.text.metadata.copyWith(color: colors.textTertiary),
            ),
          ],
          const Spacer(),
          Icon(
            Icons.keyboard_arrow_right_rounded,
            size: 20,
            color: colors.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// Server `Problem` messages, rendered like V2EX's own error block.
class _ProblemBlock extends StatelessWidget {
  const _ProblemBlock({required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(Mv2Spacing.x3),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.08),
        borderRadius: Mv2Radius.allSm,
        border: Border.all(color: colors.danger.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final problem in problems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: colors.danger,
                  ),
                  const SizedBox(width: Mv2Spacing.x2),
                  Expanded(
                    child: Text(
                      problem,
                      style: context.text.bodySmall.copyWith(
                        color: colors.danger,
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

/// Rendered Markdown preview of the draft body.
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (markdown.trim().isEmpty) {
      return Text(
        '还没有内容可预览。',
        style: context.text.body.copyWith(color: colors.textTertiary),
      );
    }
    return Mv2RichText(
      html: mv2MarkdownToHtml(markdown),
      baseStyle: context.text.reading.copyWith(color: colors.textPrimary),
    );
  }
}

/// Pinned composer toolbar (图片 + 预览/编辑 + Markdown helpers).
class _PublishToolbar extends StatelessWidget {
  const _PublishToolbar({
    required this.preview,
    required this.onTogglePreview,
    required this.onInsertImage,
    required this.emojiOpen,
    required this.onToggleEmoji,
    required this.onBold,
    required this.onCode,
    required this.onLink,
  });

  final bool preview;
  final VoidCallback onTogglePreview;
  final ValueChanged<String> onInsertImage;
  final bool emojiOpen;
  final VoidCallback onToggleEmoji;
  final VoidCallback onBold;
  final VoidCallback onCode;
  final VoidCallback onLink;

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
            // Scrolls horizontally so every action keeps a comfortable tap
            // target instead of being squeezed into equal-width cells.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Mv2Spacing.x1),
              child: Row(
                children: <Widget>[
                  if (!preview) ComposerImageButton(onInsert: onInsertImage),
                  if (!preview)
                    Mv2ToolbarButton(
                      label: '表情',
                      icon: Icons.sentiment_satisfied_alt_outlined,
                      active: emojiOpen,
                      onPressed: onToggleEmoji,
                    ),
                  Mv2ToolbarButton(
                    label: preview ? '编辑' : '预览',
                    icon: preview
                        ? Icons.edit_outlined
                        : Icons.visibility_outlined,
                    onPressed: onTogglePreview,
                  ),
                  Mv2ToolbarButton(
                    label: '粗体',
                    icon: Icons.format_bold_rounded,
                    onPressed: preview ? null : onBold,
                  ),
                  Mv2ToolbarButton(
                    label: '代码',
                    icon: Icons.code_rounded,
                    onPressed: preview ? null : onCode,
                  ),
                  Mv2ToolbarButton(
                    label: '链接',
                    icon: Icons.link_rounded,
                    onPressed: preview ? null : onLink,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned footer: Markdown hint + honesty about the local draft.
class _PublishFooter extends StatelessWidget {
  const _PublishFooter({required this.saved});

  final bool saved;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = saved ? colors.success : colors.textTertiary;

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
                saved ? Icons.check_circle : Icons.cloud_off_rounded,
                size: 15,
                color: color,
              ),
              const SizedBox(width: Mv2Spacing.x1),
              Text(
                saved ? '草稿已保存' : '草稿未保存',
                style: context.text.metadata.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet node picker; the directory comes from `/api/nodes/s2.json`.
class _NodePickerSheet extends ConsumerStatefulWidget {
  const _NodePickerSheet({this.selected});

  final String? selected;

  @override
  ConsumerState<_NodePickerSheet> createState() => _NodePickerSheetState();
}

class _NodePickerSheetState extends ConsumerState<_NodePickerSheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final nodes = ref.watch(publishNodeOptionsProvider);
    final height = MediaQuery.sizeOf(context).height * 0.72;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: <Widget>[
            const SizedBox(height: Mv2Spacing.x3),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: Mv2Radius.pill,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Mv2Spacing.pageNarrow,
                Mv2Spacing.x3,
                Mv2Spacing.pageNarrow,
                Mv2Spacing.x2,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    '选择节点',
                    style: context.text.sectionTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${nodes.value?.length ?? 0} 个',
                    style: context.text.metadata.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Mv2Spacing.pageNarrow,
              ),
              child: Mv2Surface(
                padding: const EdgeInsets.symmetric(
                  horizontal: Mv2Spacing.x3,
                  vertical: Mv2Spacing.x1,
                ),
                shadowed: false,
                child: Row(
                  children: <Widget>[
                    Icon(Icons.search, size: 18, color: colors.textTertiary),
                    const SizedBox(width: Mv2Spacing.x2),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        onChanged: (_) => setState(() {}),
                        cursorColor: colors.accent,
                        style: context.text.body.copyWith(
                          color: colors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: Mv2Spacing.x2,
                          ),
                          hintText: '搜索节点名称或 slug',
                          hintStyle: context.text.body.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Mv2Spacing.x3),
            Expanded(
              child: nodes.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Mv2StateView(
                  kind: Mv2StateKind.error,
                  compact: true,
                  title: '节点列表加载失败',
                  actionLabel: '重试',
                  onAction: () => ref.invalidate(publishNodeOptionsProvider),
                ),
                data: (all) {
                  final term = _query.text.trim().toLowerCase();
                  final filtered = term.isEmpty
                      ? all
                      : all
                            .where(
                              (node) =>
                                  node.name.toLowerCase().contains(term) ||
                                  node.key.toLowerCase().contains(term) ||
                                  node.tags.any(
                                    (tag) => tag.toLowerCase().contains(term),
                                  ),
                            )
                            .toList(growable: false);
                  if (filtered.isEmpty) {
                    return const Mv2StateView(
                      kind: Mv2StateKind.empty,
                      compact: true,
                      title: '没有匹配的节点',
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      Mv2Spacing.pageNarrow,
                      0,
                      Mv2Spacing.pageNarrow,
                      Mv2Spacing.x6 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final node = filtered[index];
                      return _NodePickerRow(
                        node: node,
                        selected: node.key == widget.selected,
                        onTap: () =>
                            Navigator.of(context)
                                .pop((slug: node.key, title: node.name)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodePickerRow extends StatelessWidget {
  const _NodePickerRow({
    required this.node,
    required this.selected,
    required this.onTap,
  });

  final V2Node node;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: Mv2Spacing.x2),
      child: Mv2Surface(
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x3,
          vertical: Mv2Spacing.x3,
        ),
        shadowed: false,
        color: selected ? colors.accentSoft : colors.surface,
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Icon(
              node.icon,
              size: 18,
              color: selected ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: Mv2Spacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    node.name,
                    style: context.text.bodyStrong.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    '/go/${node.key}',
                    style: context.text.metadata.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 18, color: colors.accent),
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder that mirrors the composer layout.
class _PublishSkeleton extends StatelessWidget {
  const _PublishSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x3,
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x8,
      ),
      children: const <Widget>[
        Mv2SkeletonBox(width: double.infinity, height: 48),
        SizedBox(height: Mv2Spacing.x3),
        Mv2SkeletonBox(width: double.infinity, height: 64),
        SizedBox(height: Mv2Spacing.x3),
        Mv2SkeletonBox(width: double.infinity, height: 240),
      ],
    );
  }
}
