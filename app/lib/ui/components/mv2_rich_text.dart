import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/parser/html_dom.dart';
import '../../core/telemetry/mv2_analytics.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../../features/reader/application/open_external_url.dart';
import 'mv2_image_viewer.dart';

/// Renders V2EX topic/reply HTML with MV2 typography.
///
/// Deliberately hand-built instead of `flutter_html`: the site markup is simple
/// (paragraphs, links, images, quotes, code, lists) and the visual tokens must
/// come from the MV2 design system, not from a third-party stylesheet.
///
/// Handled: `p/div/br`, `a`, `strong/b`, `em/i`, `code/pre`, `blockquote`,
/// `ul/ol/li`, `img`, `h1..h6`, `hr`. Everything else degrades to text.
class Mv2RichText extends StatefulWidget {
  const Mv2RichText({
    super.key,
    required this.html,
    this.baseStyle,
    this.onLinkTap,
    this.onMentionTap,
    this.onFloorRefTap,
  });

  final String html;

  /// Overrides the body text style (e.g. smaller inside a reply).
  final TextStyle? baseStyle;

  /// Intercepts internal links; defaults to go_router navigation.
  final void Function(String href)? onLinkTap;

  /// Handles `@username` mentions instead of navigating.
  ///
  /// A mention inside a reply means "this is a reply to that member's earlier
  /// comment", so reply surfaces pass a handler that opens the composer against
  /// that comment rather than jumping to the member page.
  final void Function(String username)? onMentionTap;

  /// Handles a `@user #5` floor reference — the V2EX convention for "replying
  /// to that member's comment on floor 5" — instead of leaving `#5` as dead
  /// text. The surface scrolls to and flashes the referenced floor.
  final ValueChanged<int>? onFloorRefTap;

  /// Maps a post/reply `href` onto an in-app route, or `null` when the link
  /// should open externally (`docs/12` §5).
  ///
  /// `/t/123`, `/go/python`, `/member/x` (and their absolute forms) stay inside
  /// the app; anything else is external. Exposed for tests.
  @visibleForTesting
  static String? internalRoute(String href) {
    final path = _stripHost(href);
    if (path.startsWith('/t/')) {
      final id = parseIdFromUrl(path);
      if (id == null) return null;
      // `/t/123#reply4` points at a floor; carry it so the topic page can
      // scroll to that reply instead of just opening at the top.
      final floor = RegExp(r'#reply(\d+)').firstMatch(path)?.group(1);
      return floor == null ? '/topic/$id' : '/topic/$id?floor=$floor';
    }
    if (path.startsWith('/go/')) {
      final key = RegExp(r'/go/([^/?#]+)').firstMatch(path)?.group(1);
      return key == null ? null : '/node/$key';
    }
    // `@username` mentions and member links stay in-app (`/member/:username`);
    // never open the browser for a person. The href segment is already
    // URL-encoded, so it is passed through untouched.
    final username = mentionUsername(href);
    if (username != null) return '/member/$username';
    return null;
  }

  /// The username of a `/member/{username}` link (V2EX's `@mention` form), or
  /// `null` when [href] is not one.
  @visibleForTesting
  static String? mentionUsername(String href) {
    final path = _stripHost(href);
    if (!path.startsWith('/member/')) return null;
    return RegExp(r'/member/([^/?#]+)').firstMatch(path)?.group(1);
  }

  static String _stripHost(String href) =>
      href.startsWith('https://www.v2ex.com')
      ? href.substring('https://www.v2ex.com'.length)
      : href;

  @override
  State<Mv2RichText> createState() => _Mv2RichTextState();
}

class _Mv2RichTextState extends State<Mv2RichText> {
  /// Link recognizers are owned by this state and disposed with it.
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  /// Every image in this fragment, in document order. Tapping any of them opens
  /// the full-screen viewer on this gallery, so a post's images page together
  /// (`mv2_image_viewer.dart`).
  List<String> _gallery = const <String>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style =
        widget.baseStyle ??
        context.text.reading.copyWith(color: colors.textPrimary);
    final fragment = html_parser.parseFragment(widget.html);
    _gallery = _collectImages(fragment);

    final blocks = _flow(context, fragment.nodes, style);
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _withSpacing(blocks),
    );
  }

  /// Flows a node list into block widgets.
  ///
  /// Consecutive inline nodes (`text`, `strong`, `a`, `br`, …) are merged into
  /// a single paragraph; only block-level elements start a new one. Without
  /// this, the inline parts of a sentence would each be rendered as their own
  /// separately spaced paragraph.
  ///
  /// This must run at **every** block depth, not just at the fragment root:
  /// V2EX renders Markdown topics as
  /// `div.topic_content > div.markdown_body > p…`, so a `<p>` body would
  /// otherwise take the per-child path and explode into one 12px-spaced widget
  /// per inline fragment — plus blank blocks for the whitespace between
  /// `</p> <p>`.
  List<Widget> _flow(
    BuildContext context,
    Iterable<dom.Node> nodes,
    TextStyle style,
  ) {
    final blocks = <Widget>[];
    final pending = <dom.Node>[];

    void flushInlineRun() {
      if (pending.isEmpty) return;
      final run = List<dom.Node>.of(pending);
      pending.clear();
      // Whitespace-only runs (the newline between `</p>` and `<p>`) must not
      // become blank blocks.
      if (run.map((node) => node.text).join().trim().isEmpty) return;
      blocks.add(_inlineText(context, run, style));
    }

    for (final node in nodes) {
      if (_isInline(node)) {
        pending.add(node);
        continue;
      }
      flushInlineRun();
      final widget = _block(context, node, style);
      if (widget != null) blocks.add(widget);
    }
    flushInlineRun();

    return blocks;
  }

  /// Elements that continue the current text flow instead of starting a block.
  static const Set<String> _inlineTags = <String>{
    'a',
    'strong',
    'b',
    'em',
    'i',
    'code',
    'span',
    'u',
    's',
    'del',
    'small',
    'sub',
    'sup',
    'mark',
    'br',
    'font',
    'abbr',
    'time',
  };

  static bool _isInline(dom.Node node) {
    if (node is dom.Text) return true;
    if (node is dom.Element) {
      // `<a><img></a>` is a block picture, not running text: keeping the anchor
      // inline would route it through `_spans`, which renders the anchor's
      // (empty) text and drops the image entirely.
      if (node.localName == 'a' && _linkedImage(node) != null) return false;
      return _inlineTags.contains(node.localName);
    }
    return false;
  }

  /// The `<img>` of an `<a>` that wraps exactly one image and nothing else.
  static dom.Element? _linkedImage(dom.Element anchor) {
    final meaningful = <dom.Node>[
      for (final node in anchor.nodes)
        if (node is! dom.Text || node.text.trim().isNotEmpty) node,
    ];
    if (meaningful.length != 1) return null;
    final only = meaningful.single;
    return only is dom.Element && only.localName == 'img' ? only : null;
  }

  static List<Widget> _withSpacing(
    List<Widget> blocks, [
    double spacing = Mv2Spacing.x3,
  ]) {
    final result = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) result.add(SizedBox(height: spacing));
      result.add(blocks[i]);
    }
    return result;
  }

  Widget? _block(BuildContext context, dom.Node node, TextStyle style) {
    if (node is dom.Text) {
      return _inlineText(context, <dom.Node>[node], style);
    }
    if (node is! dom.Element) return null;

    switch (node.localName) {
      case 'br':
        return const SizedBox(height: Mv2Spacing.x2);
      case 'hr':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Mv2Spacing.x1),
          child: Container(height: 1, color: context.colors.divider),
        );
      case 'p':
      case 'div':
      case 'section':
      case 'article':
        // Same inline-run grouping as the root: a paragraph's text, links and
        // `<br>`s belong to one flowing line, not to separate blocks.
        final children = _flow(context, node.nodes, style);
        if (children.isEmpty) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _withSpacing(children),
        );
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _heading(context, node);
      case 'blockquote':
        return _quote(context, node, style);
      case 'pre':
        return _code(context, node.text);
      case 'ul':
      case 'ol':
        return _list(context, node, style, ordered: node.localName == 'ol');
      case 'img':
        return _image(context, node);
      case 'a':
        // Only a linked image reaches this block path (`_isInline`).
        final image = _linkedImage(node);
        if (image != null) return _image(context, image);
        return _inlineText(context, node.nodes, style);
      default:
        return _inlineText(context, node.nodes, style);
    }
  }

  /// Markdown heading. Levels step down in size but all stay bold; `itemTitle`
  /// already carries the reading-scale multiplier, so the ratio is applied to
  /// the resolved size rather than hard-coding scaled pixels.
  Widget _heading(BuildContext context, dom.Element node) {
    final base = context.text.itemTitle;
    final ratio = switch (node.localName) {
      'h1' => 1.2,
      'h2' => 1.08,
      _ => 1.0,
    };
    final heading = base.copyWith(
      fontSize: (base.fontSize ?? 16) * ratio,
      height: 1.45,
      color: context.colors.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.only(top: Mv2Spacing.x1),
      child: _inlineText(context, node.nodes, heading),
    );
  }

  Widget _quote(BuildContext context, dom.Element node, TextStyle style) {
    final colors = context.colors;
    // Multi-paragraph quotes keep their paragraph breaks instead of being
    // flattened into one run.
    final blocks = _flow(
      context,
      node.nodes,
      style.copyWith(color: colors.textSecondary),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        Mv2Spacing.x3,
        Mv2Spacing.x2,
        Mv2Spacing.x3,
        Mv2Spacing.x2,
      ),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: Mv2Radius.allXs,
        border: Border(
          left: BorderSide(
            color: colors.accent.withValues(alpha: 0.45),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _withSpacing(blocks, Mv2Spacing.x2),
      ),
    );
  }

  Widget _code(BuildContext context, String source) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Mv2Spacing.x3),
      decoration: BoxDecoration(
        color: colors.divider,
        borderRadius: Mv2Radius.allXs,
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          source.trim(),
          style: context.text.metadata.copyWith(
            color: colors.textPrimary,
            fontFamily: 'Menlo',
            height: 1.55,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }

  /// Bullet glyph by nesting level, so a sub-list is visually distinct from its
  /// parent even though both are `ul`.
  static String _bullet(int depth) => switch (depth % 3) {
    1 => '◦',
    2 => '▪',
    _ => '•',
  };

  Widget _list(
    BuildContext context,
    dom.Element node,
    TextStyle style, {
    required bool ordered,
    int depth = 0,
  }) {
    final items = node.children
        .where((child) => child.localName == 'li')
        .toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();

    // `<ol start="3">` continues numbering from there.
    final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) children.add(const SizedBox(height: Mv2Spacing.x2));
      children.add(
        _listItem(
          context,
          items[i],
          style,
          marker: ordered ? '${start + i}.' : _bullet(depth),
          depth: depth,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _listItem(
    BuildContext context,
    dom.Element item,
    TextStyle style, {
    required String marker,
    required int depth,
  }) {
    final colors = context.colors;

    // Split the item's inline content from any nested `<ul>/<ol>`, which must
    // render *inside* the item, indented under its text.
    final inline = <dom.Node>[];
    final nested = <dom.Element>[];
    for (final child in item.nodes) {
      if (child is dom.Element &&
          (child.localName == 'ul' || child.localName == 'ol')) {
        nested.add(child);
      } else {
        inline.add(child);
      }
    }

    // Loose lists wrap item text in `<p>`; stack those runs with a tight gap
    // rather than the full paragraph spacing.
    final blocks = _flow(context, inline, style);
    final content = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) content.add(const SizedBox(height: Mv2Spacing.x1));
      content.add(blocks[i]);
    }
    for (final sub in nested) {
      content.add(const SizedBox(height: Mv2Spacing.x1));
      content.add(
        _list(
          context,
          sub,
          style,
          ordered: sub.localName == 'ol',
          depth: depth + 1,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 24,
          child: Text(
            marker,
            style: style.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: content,
          ),
        ),
      ],
    );
  }

  Widget? _image(BuildContext context, dom.Element node) {
    final colors = context.colors;
    final src = absoluteV2exUrl(node.attributes['src']);
    if (src == null) return null;
    final index = _gallery.indexOf(src);

    return Semantics(
      button: true,
      label: '查看大图',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Mv2Analytics.logImageView(source: 'content');
          showMv2ImageViewer(
            context,
            images: _gallery,
            initialIndex: index < 0 ? 0 : index,
          );
        },
        child: ClipRRect(
          borderRadius: Mv2Radius.allSm,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: Mv2Radius.allSm,
              border: Border.all(color: colors.divider),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: CachedNetworkImage(
                imageUrl: src,
                fit: BoxFit.contain,
                placeholder: (context, _) => ColoredBox(
                  color: colors.divider,
                  child: const SizedBox(height: 160, width: double.infinity),
                ),
                errorWidget: (context, _, _) => Padding(
                  padding: const EdgeInsets.all(Mv2Spacing.x3),
                  child: Text(
                    '[图片加载失败]',
                    style: context.text.metadata.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Depth-first `img` sources, matching what [_image] renders so the tapped
  /// image's position in the gallery is correct.
  static List<String> _collectImages(dom.Node root) {
    final images = <String>[];
    void visit(dom.Node node) {
      if (node is dom.Element && node.localName == 'img') {
        final src = absoluteV2exUrl(node.attributes['src']);
        if (src != null) images.add(src);
      }
      // Recurse through every node: the root is a `DocumentFragment`, not an
      // `Element`, so returning early on non-elements would find nothing.
      for (final child in node.nodes) {
        visit(child);
      }
    }

    visit(root);
    return images;
  }

  // ------------------------------------------------------------------ inline

  Widget _inlineText(
    BuildContext context,
    List<dom.Node> nodes,
    TextStyle style,
  ) {
    final spans = _spans(context, nodes, style);
    if (spans.isEmpty) return const SizedBox.shrink();
    return Text.rich(TextSpan(children: spans), style: style);
  }

  /// `#5`, `#5楼`, `#5L`, `#5层` — V2EX's floor-reference marker, matched
  /// anywhere in the body (V2EX Polish scans `/#(\d+)/g` the same way, so an
  /// explicit `#N` is treated as the authoritative target even when the `@user`
  /// sits elsewhere in the sentence).
  static final RegExp _floorRefPattern = RegExp(r'#(\d+)(?:楼|层|L)?');

  /// A `#N` (optionally `楼/层/L`) at the very start of a run, including the
  /// whitespace V2EX leaves between `@user` and `#N`.
  static final RegExp _leadingFloorRefPattern = RegExp(r'^\s*#(\d+)(?:楼|层|L)?');

  List<InlineSpan> _spans(
    BuildContext context,
    List<dom.Node> nodes,
    TextStyle style,
  ) {
    final colors = context.colors;
    final spans = <InlineSpan>[];

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is dom.Text) {
        final text = node.text;
        if (text.isEmpty) continue;
        // V2EX writes a mention as `@<a href="/member/x">x</a>`: the literal
        // `@` is a sibling of the link, so colouring only the anchor leaves a
        // two-tone `@name`. Fold the `@` into the mention's style — and into its
        // tap target, so `@user #N` still jumps to the floor as a unit.
        final mentionAnchor = text.endsWith('@')
            ? _mentionAnchorAfter(nodes, i)
            : null;
        if (mentionAnchor != null) {
          final head = text.substring(0, text.length - 1);
          if (head.isNotEmpty) {
            spans.addAll(_textWithFloorRefs(context, head, style));
          }
          final href = (nodes[mentionAnchor] as dom.Element).attributes['href']!;
          final adjacentFloor = _adjacentFloorRef(nodes, mentionAnchor, href);
          final recognizer = TapGestureRecognizer();
          if (adjacentFloor != null) {
            recognizer.onTap = () => widget.onFloorRefTap?.call(adjacentFloor);
          } else {
            recognizer.onTap = () => _openLink(context, href);
          }
          _recognizers.add(recognizer);
          spans.add(
            TextSpan(
              text: '@',
              style: style.copyWith(color: colors.accent),
              recognizer: recognizer,
            ),
          );
          continue;
        }
        spans.addAll(_textWithFloorRefs(context, text, style));
        continue;
      }
      if (node is! dom.Element) continue;

      switch (node.localName) {
        case 'br':
          spans.add(const TextSpan(text: '\n'));
        case 'strong':
        case 'b':
          spans.addAll(
            _spans(
              context,
              node.nodes,
              style.copyWith(fontWeight: FontWeight.w600),
            ),
          );
        case 'em':
        case 'i':
          spans.addAll(
            _spans(
              context,
              node.nodes,
              style.copyWith(fontStyle: FontStyle.italic),
            ),
          );
        case 'code':
          spans.add(
            TextSpan(
              text: node.text,
              style: style.copyWith(
                fontFamily: 'Menlo',
                fontSize: (style.fontSize ?? 15) * 0.92,
                height: 1.4,
                letterSpacing: 0,
                backgroundColor: colors.divider,
              ),
            ),
          );
        case 'a':
          final href = node.attributes['href'];
          // `@user #5`: the name itself is part of the floor reference, so it
          // jumps too — the user asked for "click → go to floor 5", and the
          // name is the big tap target. A plain `@user` still falls through to
          // the mention handler (composer).
          final adjacentFloor = _adjacentFloorRef(nodes, i, href);
          TapGestureRecognizer? recognizer;
          if (adjacentFloor != null) {
            recognizer = TapGestureRecognizer()
              ..onTap = () => widget.onFloorRefTap?.call(adjacentFloor);
            _recognizers.add(recognizer);
          } else if (href != null) {
            recognizer = TapGestureRecognizer()
              ..onTap = () => _openLink(context, href);
            _recognizers.add(recognizer);
          }
          spans.add(
            TextSpan(
              text: node.text,
              style: style.copyWith(color: colors.accent),
              recognizer: recognizer,
            ),
          );
          if (adjacentFloor != null && i + 1 < nodes.length) {
            final next = nodes[i + 1];
            if (next is dom.Text) {
              // Glue the badge to the name's top-right and swallow the `#N`
              // (plus the whitespace before it) from the following text run.
              spans.add(_floorRefBadge(context, adjacentFloor, attached: true));
              final match = _leadingFloorRefPattern.firstMatch(next.text)!;
              final rest = next.text.substring(match.end);
              if (rest.isNotEmpty) {
                spans.addAll(_textWithFloorRefs(context, rest, style));
              }
              i++;
            }
          }
        default:
          spans.addAll(_spans(context, node.nodes, style));
      }
    }
    return spans;
  }

  /// Splits [text] on `#N` floor references, rendering each as a jump chip.
  ///
  /// Runs only on reply surfaces (a non-null [Mv2RichText.onFloorRefTap]);
  /// elsewhere `#N` stays plain text.
  List<InlineSpan> _textWithFloorRefs(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    if (widget.onFloorRefTap == null) {
      return _textWithDecodeHint(context, text, style);
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _floorRefPattern.allMatches(text)) {
      final floor = int.tryParse(match.group(1)!);
      if (floor == null) continue;
      if (match.start > cursor) {
        spans.addAll(
          _textWithDecodeHint(
            context,
            text.substring(cursor, match.start),
            style,
          ),
        );
      }
      spans.add(_floorRefBadge(context, floor, attached: false));
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.addAll(_textWithDecodeHint(context, text.substring(cursor), style));
    }
    return spans;
  }

  /// Index of the `/member/…` anchor that renders the mention directly after
  /// `nodes[index]`, or `null`.
  ///
  /// V2EX emits `@<a href="/member/x">x</a>`, so the literal `@` is a sibling of
  /// the link rather than part of it; the text run needs to find the anchor to
  /// style and wire both halves as one mention. Whitespace-only text nodes
  /// between the two are tolerated.
  int? _mentionAnchorAfter(List<dom.Node> nodes, int index) {
    for (var j = index + 1; j < nodes.length; j++) {
      final next = nodes[j];
      if (next is dom.Text) {
        if (next.text.trim().isEmpty) continue;
        return null;
      }
      if (next is! dom.Element || next.localName != 'a') return null;
      final href = next.attributes['href'];
      return (href != null && Mv2RichText.mentionUsername(href) != null)
          ? j
          : null;
    }
    return null;
  }

  /// The floor in a `#N` immediately following the mention at `nodes[index]`,
  /// or `null`. Lets the mention's own tap jump to the floor (its name is the
  /// larger tap target) instead of opening the composer.
  int? _adjacentFloorRef(List<dom.Node> nodes, int index, String? href) {
    if (href == null || widget.onFloorRefTap == null) return null;
    if (Mv2RichText.mentionUsername(href) == null) return null;
    if (index + 1 >= nodes.length) return null;
    final next = nodes[index + 1];
    if (next is! dom.Text) return null;
    final match = _leadingFloorRefPattern.firstMatch(next.text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// Small filled superscript badge for a `#N` floor reference.
  ///
  /// [attached] glues it to the mention's top-right (`@user #5` in V2EX drops
  /// the whitespace, so the badge hugs the name); otherwise a standalone `#5`
  /// keeps a little breathing room. Tapping it jumps to the floor.
  InlineSpan _floorRefBadge(
    BuildContext context,
    int floor, {
    required bool attached,
  }) {
    final colors = context.colors;
    return WidgetSpan(
      // Top alignment rides the badge on the line's ascent, like a footnote.
      alignment: PlaceholderAlignment.top,
      child: Padding(
        padding: EdgeInsets.only(left: attached ? 1 : 3, right: 1, top: 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onFloorRefTap?.call(floor),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '#$floor',
              style: context.text.badge.copyWith(
                color: colors.accentContrast,
                fontSize: 10,
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// V2EX sometimes renders links as bare base64 runs; mirroring the legacy
  /// client we offer a one-tap decode that copies the result.
  List<InlineSpan> _textWithDecodeHint(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final match = RegExp(r'[A-Za-z0-9+/]{16,}={0,2}').firstMatch(text);
    if (match == null) return <InlineSpan>[TextSpan(text: text)];

    final candidate = match.group(0)!;
    final decoded = _tryDecodeBase64(candidate);
    if (decoded == null) return <InlineSpan>[TextSpan(text: text)];

    return <InlineSpan>[
      TextSpan(text: text.substring(0, match.start)),
      TextSpan(text: candidate, style: style),
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: decoded));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已解码并复制')));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: context.colors.accentSoft,
                borderRadius: Mv2Radius.allXs,
              ),
              child: Text(
                '解码',
                style: context.text.badge.copyWith(
                  color: context.colors.accent,
                ),
              ),
            ),
          ),
        ),
      ),
      TextSpan(text: text.substring(match.end)),
    ];
  }

  String? _tryDecodeBase64(String value) {
    try {
      final bytes = const Base64Decoder().convert(value);
      final decoded = String.fromCharCodes(bytes);
      if (decoded.isEmpty) return null;
      final printable = decoded.runes
          .where((rune) => rune >= 0x20 && rune < 0x7F)
          .length;
      if (printable / decoded.length < 0.8) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openLink(BuildContext context, String href) async {
    if (widget.onLinkTap != null) {
      widget.onLinkTap!(href);
      return;
    }
    // A mention is a reply-to marker on reply surfaces; let the caller handle
    // it before the generic `/member/x` mapping.
    final mention = Mv2RichText.mentionUsername(href);
    if (mention != null && widget.onMentionTap != null) {
      widget.onMentionTap!(mention);
      return;
    }
    final target = Mv2RichText.internalRoute(href);
    if (target != null) {
      Mv2Analytics.logLinkOpen(mode: 'internal', isInternal: true);
      context.push(target);
      return;
    }
    // External: reader / 原文 / browser — shared with the link-preview card.
    await openExternalUrl(context, href);
  }
}
