import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/parser/publish_parser.dart';

/// Representative `/new` markup.
///
/// The live page could not be captured from this environment (see `docs/13`
/// §7), so the fixture mirrors the documented contract: a session `once` input,
/// a `node_name` select, and the shared `div.problem` rejection block. Selector
/// coverage is the point — the exact wrapper nesting is deliberately redundant
/// so a markup tweak on one arm does not break publishing silently.
const String _formHtml = '''
<html><body>
<div id="Wrapper">
  <div class="cell">
    <form method="post" action="/new">
      <input type="hidden" value="95271" name="once" />
      <select name="node_name">
        <option value="programmer">程序员</option>
        <option value="create" selected>分享创造</option>
        <option value="qna">问与答</option>
      </select>
      <input type="text" class="sl" name="title" maxlength="120" />
      <textarea name="content"></textarea>
    </form>
  </div>
</div>
</body></html>
''';

void main() {
  group('PublishParser.parseForm', () {
    test('reads once, the selected node and the option list', () {
      final form = PublishParser.parseForm(_formHtml);

      expect(form, isNotNull);
      expect(form!.once, '95271');
      expect(form.defaultNode, 'create');
      expect(form.nodeOptions.map((option) => option.name), <String>[
        'programmer',
        'create',
        'qna',
      ]);
      expect(form.nodeOptions.first.title, '程序员');
    });

    test('accepts the input#once variant used by topic pages', () {
      const html = '''
        <div id="Wrapper">
          <input type="hidden" id="once" value="777" />
          <input type="hidden" name="node_name" value="apple" />
        </div>
      ''';

      final form = PublishParser.parseForm(html);

      expect(form!.once, '777');
      expect(form.defaultNode, 'apple');
      expect(form.nodeOptions, isEmpty);
    });

    test('prefers the node in the URL over the page default', () {
      final form = PublishParser.parseForm(_formHtml, pathNode: 'ai');
      expect(form!.defaultNode, 'ai');
    });

    test('returns null when the page carries no once', () {
      expect(PublishParser.parseForm('<div id="Wrapper"></div>'), isNull);
      expect(PublishParser.parseForm('<html><body>nope</body></html>'), isNull);
    });
  });

  group('PublishParser.parseErrors', () {
    test('parses the shared problem block', () {
      const html = '''
        <div class="problem">
          <ul><li>主题标题不能为空</li><li>请不要频繁操作</li></ul>
        </div>
      ''';
      expect(PublishParser.parseErrors(html), <String>['主题标题不能为空', '请不要频繁操作']);
    });

    test('returns an empty list for a clean page', () {
      expect(PublishParser.parseErrors('<html></html>'), isEmpty);
    });
  });

  group('PublishParser.parseTopicId', () {
    test('extracts the id from the success redirect', () {
      expect(PublishParser.parseTopicId('/t/123456'), 123456);
      expect(
        PublishParser.parseTopicId('https://www.v2ex.com/t/9800#reply1'),
        9800,
      );
    });

    test('returns null for non-topic redirects', () {
      expect(PublishParser.parseTopicId('/signin'), isNull);
      expect(PublishParser.parseTopicId('/new'), isNull);
      expect(PublishParser.parseTopicId(null), isNull);
    });
  });

  group('PublishParser.isStaleToken', () {
    test('true when the form is handed back without a problem', () {
      expect(PublishParser.isStaleToken(_formHtml), isTrue);
    });

    test('false when the rejection explains itself', () {
      const html = '''
        <div id="Wrapper">
          <div class="problem"><ul><li>主题标题不能为空</li></ul></div>
          <form action="/new">
            <input type="hidden" name="once" value="95271" />
            <textarea name="content"></textarea>
          </form>
        </div>
      ''';
      expect(PublishParser.isStaleToken(html), isFalse);
    });

    test('false for a page that is not the topic form', () {
      expect(
        PublishParser.isStaleToken('<html><body>hello</body></html>'),
        isFalse,
      );
      expect(
        PublishParser.isStaleToken('<input id="once" value="7">'),
        isFalse,
      );
    });
  });
}
