import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/shared/format/mv2_markdown.dart';

void main() {
  group('mv2MarkdownToHtml', () {
    test('renders headings and paragraphs', () {
      expect(mv2MarkdownToHtml('# 标题'), '<h1>标题</h1>');
      expect(mv2MarkdownToHtml('一行\n接着一行'), '<p>一行<br>接着一行</p>');
      expect(mv2MarkdownToHtml('一\n\n二'), '<p>一</p><p>二</p>');
    });

    test('renders emphasis, code spans and links', () {
      expect(mv2MarkdownToHtml('**粗**'), '<p><strong>粗</strong></p>');
      expect(mv2MarkdownToHtml('*斜*'), '<p><em>斜</em></p>');
      expect(mv2MarkdownToHtml('`a < b`'), '<p><code>a &lt; b</code></p>');
      expect(
        mv2MarkdownToHtml('[V2EX](https://v2ex.com)'),
        '<p><a href="https://v2ex.com">V2EX</a></p>',
      );
      expect(
        mv2MarkdownToHtml('![图](https://x/y.png)'),
        '<p><img src="https://x/y.png" alt="图"></p>',
      );
    });

    test('keeps code spans literal inside bold', () {
      expect(
        mv2MarkdownToHtml('**`x`**'),
        '<p><strong><code>x</code></strong></p>',
      );
    });

    test('renders lists and quotes', () {
      expect(mv2MarkdownToHtml('- a\n- b'), '<ul><li>a</li><li>b</li></ul>');
      expect(mv2MarkdownToHtml('1. a\n2. b'), '<ol><li>a</li><li>b</li></ol>');
      expect(mv2MarkdownToHtml('> 引用'), '<blockquote>引用</blockquote>');
    });

    test('renders fenced code without inline processing', () {
      expect(
        mv2MarkdownToHtml('```\n**not bold**\n```'),
        '<pre><code>**not bold**</code></pre>',
      );
    });

    test('renders horizontal rules', () {
      expect(mv2MarkdownToHtml('---'), '<hr>');
    });

    test('escapes HTML in user input', () {
      expect(
        mv2MarkdownToHtml('<script>alert(1)</script>'),
        '<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>',
      );
    });

    test('returns an empty string for an empty draft', () {
      expect(mv2MarkdownToHtml(''), '');
    });
  });
}
