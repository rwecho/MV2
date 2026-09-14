import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/shared/emoji/mv2_emoji_library.dart';

/// The picker mirrors V2EX Polish's library, and the `[token]` shortcodes must
/// become hosted image URLs before the body is submitted (that is what V2EX
/// renders).
void main() {
  group('Mv2EmojiLibrary', () {
    test('mirrors V2EX Polish group titles and sizes', () {
      expect(
        Mv2EmojiLibrary.groups.map((group) => group.title).toList(),
        <String>['流行', '小黄脸', '手势', '庆祝', '其他'],
      );
      expect(Mv2EmojiLibrary.groups.first.emoji, hasLength(31));
      expect(Mv2EmojiLibrary.allTokens.length, 103);
    });

    test('the 流行 group carries hosted previews, the rest are glyphs', () {
      final popular = Mv2EmojiLibrary.groups.first;
      expect(popular.emoji.first.token, '[脱单doge]');
      expect(popular.emoji.first.imageUrl, startsWith('https://i.imgur.com/'));
      expect(
        popular.emoji.every((emoji) => emoji.imageUrl?.startsWith('http') ?? false),
        isTrue,
      );

      final faces = Mv2EmojiLibrary.groups[1];
      expect(faces.emoji.first.token, '😀');
      expect(
        faces.emoji.every((emoji) => emoji.imageUrl == null),
        isTrue,
      );
    });

    test('contains the well-known shortcodes', () {
      expect(Mv2EmojiLibrary.allTokens, contains('[doge]'));
      expect(Mv2EmojiLibrary.allTokens, contains('[吃瓜]'));
      // 小红书 variants keep their `R` suffix, exactly like the userscript.
      expect(Mv2EmojiLibrary.allTokens, contains('[偷笑R]'));
      expect(Mv2EmojiLibrary.allTokens, contains('👍'));
    });
  });

  group('expandForSubmit', () {
    test('replaces known tokens with the hosted low-definition URL', () {
      expect(
        Mv2EmojiLibrary.expandForSubmit('你好 [doge] 再见'),
        '你好 https://i.imgur.com/agAJ0Rd.png  再见',
      );
    });

    test('leaves plain text, unicode emoji and unknown brackets alone', () {
      expect(Mv2EmojiLibrary.expandForSubmit('😀 你好'), '😀 你好');
      expect(Mv2EmojiLibrary.expandForSubmit('[不是表情]'), '[不是表情]');
      expect(Mv2EmojiLibrary.expandForSubmit(''), '');
    });

    test('expands every popular token in one pass', () {
      final text =
          Mv2EmojiLibrary.groups.first.emoji
              .map((emoji) => emoji.token)
              .join(' ');
      final expanded = Mv2EmojiLibrary.expandForSubmit(text);
      expect(expanded, isNot(contains('[')));
      expect(expanded, contains('https://i.imgur.com/'));
    });
  });
}
