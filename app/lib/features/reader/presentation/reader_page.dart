import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_rich_text.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../settings/application/settings_controller.dart';
import '../application/reader_mode.dart';
import '../data/reader_article.dart';
import '../data/reader_extractor.dart';
import 'reader_failure_view.dart';

/// In-app reader for an external link.
///
/// One live [WebViewController] backs the whole page: it is the visible loading
/// surface, it *is* 原文 mode, and it supplies the DOM that Readability parses
/// for 阅读 mode. Switching modes only swaps which layer is painted, so the
/// page is never reloaded.
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.url, this.mode});

  /// Absolute `http(s)` URL to open.
  final String url;

  /// Optional starting mode from `/reader?url=…&mode=reader|original`. When
  /// absent the persisted 外链打开方式 setting decides.
  final String? mode;

  /// Height of the floating glass header; reader content is padded by it.
  static const double headerHeight = 52;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  /// Extraction budget after `onPageFinished`; on expiry the page falls back to
  /// 原文.
  static const Duration _extractionTimeout = Duration(seconds: 10);
  static const Duration _noticeDuration = Duration(seconds: 4);

  late final WebViewController? _controller;
  late final Uri? _uri;
  late final ReaderMode _initialMode;
  late ReaderMode _mode;

  ReaderArticle? _article;
  String? _documentTitle;
  String? _notice;
  Object? _webError;

  bool _pageLoading = true;
  bool _extracting = false;

  /// True once the user has picked a mode from the sheet, which disables the
  /// automatic switch to 阅读 when extraction lands.
  bool _userToggled = false;

  /// Guards against a stale `onPageFinished` from a superseded navigation.
  int _loadGeneration = 0;

  Timer? _extractionTimer;
  Timer? _noticeTimer;

  bool get _hasUrl =>
      _uri != null && (_uri.isScheme('http') || _uri.isScheme('https'));

  @override
  void initState() {
    super.initState();
    _uri = Uri.tryParse(widget.url.trim());
    _initialMode = initialReaderMode(
      queryMode: widget.mode,
      setting: ref.read(settingsProvider).openLinkMode,
    );
    _mode = _initialMode;

    if (!_hasUrl) {
      _controller = null;
      _webError = 'invalid-url';
      _pageLoading = false;
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: _onPageStarted,
          onPageFinished: _onPageFinished,
          onWebResourceError: _onWebResourceError,
        ),
      )
      ..loadRequest(_uri!);
  }

  @override
  void dispose() {
    _extractionTimer?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }

  // --------------------------------------------------------------- loading

  void _onPageStarted(String url) {
    _loadGeneration++;
    if (!mounted) return;
    setState(() {
      _pageLoading = true;
      _webError = null;
    });
  }

  void _onPageFinished(String url) {
    final generation = _loadGeneration;
    if (!mounted) return;
    setState(() => _pageLoading = false);
    unawaited(_afterPageFinished(url, generation));
  }

  void _onWebResourceError(WebResourceError error) {
    // Sub-resource failures (an ad, a tracker) must not blank the page.
    if (error.isForMainFrame == false) return;
    if (!mounted) return;
    _extractionTimer?.cancel();
    setState(() {
      _webError = error;
      _pageLoading = false;
      _extracting = false;
    });
  }

  Future<void> _afterPageFinished(String url, int generation) async {
    try {
      final title = await _controller?.getTitle();
      final trimmed = title?.trim();
      if (mounted && trimmed != null && trimmed.isNotEmpty) {
        setState(() => _documentTitle = trimmed);
      }
    } catch (_) {
      // A missing title is not a failure: the header falls back to Readability
      // then the URL host.
    }
    if (!mounted || generation != _loadGeneration) return;
    await _extract(url);
  }

  // ------------------------------------------------------------- extraction

  Future<void> _extract(String url) async {
    final controller = _controller;
    if (controller == null) return;

    _extractionTimer?.cancel();
    setState(() => _extracting = true);
    _extractionTimer = Timer(_extractionTimeout, _onExtractionFailed);

    ReaderArticle? article;
    try {
      final source = await ref.read(readabilitySourceProvider.future);
      if (!mounted) return;
      article = await ReaderExtractor(
        controller,
        source,
      ).extract(url);
    } catch (error, stackTrace) {
      debugPrint('MV2: reader extraction failed: $error\n$stackTrace');
      article = null;
    }
    if (!mounted) return;
    _extractionTimer?.cancel();

    if (article == null) {
      _onExtractionFailed();
      return;
    }
    setState(() {
      _article = article;
      _extracting = false;
      // Only auto-show the reader when that is how the page was opened; an
      // explicit 原文 visit or a manual switch must not be overridden.
      if (!_userToggled && _initialMode == ReaderMode.reader) {
        _mode = ReaderMode.reader;
      }
    });
  }

  void _onExtractionFailed() {
    _extractionTimer?.cancel();
    if (!mounted) return;
    final switched = !_userToggled && _mode == ReaderMode.reader;
    setState(() {
      _extracting = false;
      if (switched) _mode = ReaderMode.original;
    });
    if (switched) _showNotice('无法提取正文，已切换到原文');
  }

  void _showNotice(String text) {
    _noticeTimer?.cancel();
    setState(() => _notice = text);
    _noticeTimer = Timer(_noticeDuration, () {
      if (mounted) setState(() => _notice = null);
    });
  }

  // ------------------------------------------------------------------ modes

  void _setMode(ReaderMode mode) {
    if (mode == ReaderMode.reader && _article == null) return;
    _userToggled = true;
    setState(() => _mode = mode);
  }

  // ---------------------------------------------------------------- actions

  Future<void> _openExternal() async {
    final uri = _uri;
    if (uri == null) return;
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('无法打开浏览器')));
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('链接已复制')));
  }

  Future<void> _share() async {
    final text = '$_displayTitle  ${widget.url}';
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = (box != null && box.hasSize)
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: origin),
      );
    } catch (error, stackTrace) {
      debugPrint('MV2: share failed: $error\n$stackTrace');
      try {
        await Clipboard.setData(ClipboardData(text: widget.url));
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开分享面板，链接已复制到剪贴板')));
    }
  }

  void _showOverflowSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.elevatedSurface,
      shape: const RoundedRectangleBorder(borderRadius: Mv2Radius.allXl),
      builder: (sheetContext) => _ReaderOverflowSheet(
        mode: _mode,
        canUseReader: _article != null,
        onSelectMode: (ReaderMode mode) {
          Navigator.of(sheetContext).pop();
          _setMode(mode);
        },
        onOpenExternal: () {
          Navigator.of(sheetContext).pop();
          unawaited(_openExternal());
        },
        onCopyLink: () {
          Navigator.of(sheetContext).pop();
          unawaited(_copyLink());
        },
        onShare: () {
          Navigator.of(sheetContext).pop();
          unawaited(_share());
        },
      ),
    );
  }

  // ------------------------------------------------------------------ build

  /// WebView document title → Readability title → URL host.
  String get _displayTitle {
    final document = _documentTitle?.trim();
    if (document != null && document.isNotEmpty) return document;
    final article = _article?.title?.trim();
    if (article != null && article.isNotEmpty) return article;
    final host = _uri?.host.trim();
    if (host != null && host.isNotEmpty) return host;
    return '阅读模式';
  }

  String get _failureDescription {
    if (!_hasUrl) return '链接无效，无法打开。';
    final error = _webError;
    if (error is WebResourceError && error.description.trim().isNotEmpty) {
      return '网页加载失败：${error.description.trim()}';
    }
    return '网页加载失败，请检查网络后重试，或用浏览器打开。';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final controller = _controller;
    final article = _article;
    final showReader = _mode == ReaderMode.reader && article != null;
    final failed = _webError != null;

    return Mv2PageScaffold(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 原文 layer — mounted for the whole lifetime so a mode switch never
          // reloads the page.
          if (controller != null && !failed)
            WebViewWidget(controller: controller),
          if (failed)
            ReaderFailureView(
              description: _failureDescription,
              onOpenExternal: () => unawaited(_openExternal()),
            ),
          // 阅读 layer — an opaque native article over the WebView.
          if (showReader)
            _ReaderBody(
              article: article,
              title: _displayTitle,
              topInset: ReaderPage.headerHeight + Mv2Spacing.x2,
            ),
          if ((_pageLoading || _extracting) && !failed)
            Positioned(
              top: ReaderPage.headerHeight,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                color: colors.accent,
                backgroundColor: colors.divider,
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _ReaderHeader(
              title: _displayTitle,
              onBack: () => context.pop(),
              onMore: _showOverflowSheet,
            ),
          ),
          if (_notice != null)
            Positioned(
              top: ReaderPage.headerHeight + Mv2Spacing.x2,
              left: Mv2Spacing.pageNarrow,
              right: Mv2Spacing.pageNarrow,
              child: IgnorePointer(child: _ReaderNotice(text: _notice!)),
            ),
        ],
      ),
    );
  }
}

/// Floating frosted header: back · page title · overflow.
class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.title,
    required this.onBack,
    required this.onMore,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Mv2GlassSurface(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(Mv2Radius.lgValue),
      ),
      blur: 20,
      padding: const EdgeInsets.symmetric(horizontal: Mv2Spacing.x1),
      child: SizedBox(
        height: ReaderPage.headerHeight,
        child: Row(
          children: <Widget>[
            Mv2IconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 18,
              tooltip: '返回',
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.text.itemTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            Mv2IconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: '更多操作',
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }
}

/// The native MV2 article, rendered over the WebView.
class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.article,
    required this.title,
    required this.topInset,
  });

  final ReaderArticle article;
  final String title;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = context.text.reading.copyWith(color: colors.textPrimary);
    final width = MediaQuery.sizeOf(context).width;
    final padding = Mv2Spacing.pageHorizontal(width);

    final meta = <String>[
      if (article.byline != null) article.byline!,
      if (article.siteName != null) article.siteName!,
      '约 ${article.readingMinutes} 分钟',
    ].join(' · ');

    return ColoredBox(
      color: colors.background,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          padding,
          topInset,
          padding,
          // Lets the final lines scroll clear of the floating header instead of
          // ending flush against the viewport edge.
          Mv2Spacing.x10 + topInset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: context.text.topicTitleLarge.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: Mv2Spacing.x2),
            Text(
              meta,
              style: context.text.metadata.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: Mv2Spacing.x3),
            Container(height: 1, color: colors.divider),
            const SizedBox(height: Mv2Spacing.x4),
            Mv2RichText(html: article.contentHtml, baseStyle: base),
          ],
        ),
      ),
    );
  }
}

/// Subtle pill used for the "could not extract" fallback message.
class _ReaderNotice extends StatelessWidget {
  const _ReaderNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x4,
          vertical: Mv2Spacing.x2,
        ),
        decoration: BoxDecoration(
          color: colors.elevatedSurface,
          borderRadius: Mv2Radius.pill,
          border: Border.all(color: colors.border),
        ),
        child: Text(
          text,
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

/// `⋯` sheet: 阅读/原文 mode choice, then the three escape actions.
///
/// Mirrors the settings `_SelectionSheet` metrics (title padding + ≥48px rows).
class _ReaderOverflowSheet extends StatelessWidget {
  const _ReaderOverflowSheet({
    required this.mode,
    required this.canUseReader,
    required this.onSelectMode,
    required this.onOpenExternal,
    required this.onCopyLink,
    required this.onShare,
  });

  final ReaderMode mode;
  final bool canUseReader;
  final ValueChanged<ReaderMode> onSelectMode;
  final VoidCallback onOpenExternal;
  final VoidCallback onCopyLink;
  final VoidCallback onShare;

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
          for (final ReaderMode option in ReaderMode.values)
            _SheetChoice(
              label: option.label,
              selected: option == mode,
              enabled: option != ReaderMode.reader || canUseReader,
              onTap: () => onSelectMode(option),
            ),
          _SheetAction(
            icon: Icons.open_in_browser_rounded,
            label: '用浏览器打开',
            onTap: onOpenExternal,
          ),
          _SheetAction(
            icon: Icons.link_rounded,
            label: '复制链接',
            onTap: onCopyLink,
          ),
          _SheetAction(
            icon: Icons.ios_share_rounded,
            label: '分享',
            onTap: onShare,
          ),
          const SizedBox(height: Mv2Spacing.x3),
        ],
      ),
    );
  }
}

/// Single-choice row with a trailing check on the active mode.
class _SheetChoice extends StatelessWidget {
  const _SheetChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = !enabled
        ? colors.textTertiary
        : (selected ? colors.accent : colors.textPrimary);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: Mv2Spacing.minTapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x4,
          vertical: Mv2Spacing.x3,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: context.text.body.copyWith(color: fg)),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 20, color: colors.accent),
          ],
        ),
      ),
    );
  }
}

/// Non-selecting action row (icon + label), like the topic overflow sheet.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
            Icon(icon, size: 20, color: colors.textSecondary),
            const SizedBox(width: Mv2Spacing.x3),
            Expanded(
              child: Text(
                label,
                style: context.text.body.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
