/// Minimal Markdown → HTML for the composer's 预览 pane.
///
/// V2EX renders the `syntax=default` topic body as Markdown, so the client has
/// to show something representative before submitting. This deliberately
/// implements only the subset the site actually supports — no tables, no
/// footnotes, no HTML passthrough — and escapes everything, because the result
/// is fed straight into [Mv2RichText].
///
/// Supported: `#`–`######` headings, fenced code, `>` quotes, `-`/`*` and
/// `1.` lists, `---` rules, `**bold**`, `*italic*`, `` `code` ``,
/// `[text](url)` and `![alt](url)`.
String mv2MarkdownToHtml(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <String>[];

  // Consecutive list / quote lines belong to one block.
  final paragraph = <String>[];
  final listItems = <String>[];
  String? listTag;
  final quoteLines = <String>[];
  final codeLines = <String>[];
  bool inFence = false;

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add('<p>${paragraph.map(_inline).join('<br>')}</p>');
    paragraph.clear();
  }

  void flushList() {
    if (listItems.isEmpty) return;
    final tag = listTag ?? 'ul';
    blocks.add(
      '<$tag>${listItems.map((item) => '<li>${_inline(item)}</li>').join()}</$tag>',
    );
    listItems.clear();
    listTag = null;
  }

  void flushQuote() {
    if (quoteLines.isEmpty) return;
    blocks.add(
      '<blockquote>${quoteLines.map(_inline).join('<br>')}</blockquote>',
    );
    quoteLines.clear();
  }

  void flushAll() {
    flushParagraph();
    flushList();
    flushQuote();
  }

  for (final raw in lines) {
    final line = raw.trimRight();

    if (line.trimLeft().startsWith('```')) {
      if (inFence) {
        blocks.add('<pre><code>${_escape(codeLines.join('\n'))}</code></pre>');
        codeLines.clear();
        inFence = false;
      } else {
        flushAll();
        inFence = true;
      }
      continue;
    }
    if (inFence) {
      codeLines.add(line);
      continue;
    }

    if (line.trim().isEmpty) {
      flushAll();
      continue;
    }

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      flushAll();
      final level = heading.group(1)!.length;
      blocks.add('<h$level>${_inline(heading.group(2)!)}</h$level>');
      continue;
    }

    if (RegExp(r'^\s*([-*_])\s*\1\s*\1[\s\-*_]*$').hasMatch(line)) {
      flushAll();
      blocks.add('<hr>');
      continue;
    }

    final quote = RegExp(r'^>\s?(.*)$').firstMatch(line);
    if (quote != null) {
      flushParagraph();
      flushList();
      quoteLines.add(quote.group(1)!);
      continue;
    }

    final bullet = RegExp(r'^\s*[-*+]\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      flushQuote();
      if (listTag != 'ul') flushList();
      listTag = 'ul';
      listItems.add(bullet.group(1)!);
      continue;
    }

    final ordered = RegExp(r'^\s*\d+[.)]\s+(.*)$').firstMatch(line);
    if (ordered != null) {
      flushParagraph();
      flushQuote();
      if (listTag != 'ol') flushList();
      listTag = 'ol';
      listItems.add(ordered.group(1)!);
      continue;
    }

    flushList();
    flushQuote();
    paragraph.add(line);
  }

  if (inFence && codeLines.isNotEmpty) {
    blocks.add('<pre><code>${_escape(codeLines.join('\n'))}</code></pre>');
  }
  flushAll();

  return blocks.join();
}

/// Inline spans. Code spans are stashed first so `**` inside them is literal.
String _inline(String source) {
  final stash = <String>[];
  var text = _escape(source);

  text = text.replaceAllMapped(RegExp(r'`([^`]+)`'), (match) {
    stash.add('<code>${match.group(1)}</code>');
    return '\u0000${stash.length - 1}\u0000';
  });

  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\(([^)\s]+)\)'),
    (match) => '<img src="${match.group(2)}" alt="${match.group(1)}">',
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)'),
    (match) => '<a href="${match.group(2)}">${match.group(1)}</a>',
  );
  text = text.replaceAllMapped(
    RegExp(r'\*\*([^*]+)\*\*'),
    (match) => '<strong>${match.group(1)}</strong>',
  );
  text = text.replaceAllMapped(
    RegExp(r'__([^_]+)__'),
    (match) => '<strong>${match.group(1)}</strong>',
  );
  text = text.replaceAllMapped(
    RegExp(r'(?<![\w*])\*([^*\n]+)\*(?![\w*])'),
    (match) => '<em>${match.group(1)}</em>',
  );

  return text.replaceAllMapped(
    RegExp('\u0000(\\d+)\u0000'),
    (match) => stash[int.parse(match.group(1)!)],
  );
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
