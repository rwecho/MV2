import 'package:flutter/foundation.dart';

/// Emoji library mirrored from **V2EX Polish** (`coolpace/V2EX_Polish`,
/// `src/constants.ts`), so the app offers the same set the popular userscript
/// does.
///
/// The 流行 group is Bilibili / 小红书 emoji that V2EX has no markup for: V2EX
/// Polish inserts the readable token (`[doge]`) into the editor and, **when
/// submitting**, replaces it with the hosted image URL — V2EX then renders that
/// URL as an image. [Mv2EmojiLibrary.expandForSubmit] performs the same
/// replacement, so the editor stays readable while the post still renders.

@immutable
class Mv2Emoji {
  const Mv2Emoji(this.token, {this.imageUrl});

  /// What the editor receives: `[doge]` (流行) or a Unicode glyph.
  final String token;

  /// High-definition preview for the 流行 set; `null` for Unicode glyphs.
  final String? imageUrl;
}

@immutable
class Mv2EmojiGroup {
  const Mv2EmojiGroup(this.title, this.emoji);

  final String title;
  final List<Mv2Emoji> emoji;
}

abstract final class Mv2EmojiLibrary {
  /// Grouped emoji, in V2EX Polish's order (流行 / 小黄脸 / 手势 / 庆祝 / 其他).
  static const List<Mv2EmojiGroup> groups = <Mv2EmojiGroup>[
    Mv2EmojiGroup('流行', <Mv2Emoji>[
      Mv2Emoji('[脱单doge]', imageUrl: 'https://i.imgur.com/3mPhudo.png'),
      Mv2Emoji('[doge]', imageUrl: 'https://i.imgur.com/HZL0hOa.png'),
      Mv2Emoji('[打call]', imageUrl: 'https://i.imgur.com/4GfTlV0.png'),
      Mv2Emoji('[星星眼]', imageUrl: 'https://i.imgur.com/oEIJRru.png'),
      Mv2Emoji('[吃瓜]', imageUrl: 'https://i.imgur.com/Gy3nwkC.png'),
      Mv2Emoji('[OK]', imageUrl: 'https://i.imgur.com/PE2dyjY.png'),
      Mv2Emoji('[哦呼]', imageUrl: 'https://i.imgur.com/CXXgF4E.png'),
      Mv2Emoji('[思考]', imageUrl: 'https://i.imgur.com/eRJTCx7.png'),
      Mv2Emoji('[疑惑]', imageUrl: 'https://i.imgur.com/3gCygBS.png'),
      Mv2Emoji('[辣眼睛]', imageUrl: 'https://i.imgur.com/A5WXoZJ.png'),
      Mv2Emoji('[傲娇]', imageUrl: 'https://i.imgur.com/m7IlCrD.png'),
      Mv2Emoji('[捂脸]', imageUrl: 'https://i.imgur.com/fLp3t8s.png'),
      Mv2Emoji('[无语]', imageUrl: 'https://i.imgur.com/wMfcBqD.png'),
      Mv2Emoji('[大哭]', imageUrl: 'https://i.imgur.com/SNHJxtv.png'),
      Mv2Emoji('[酸了]', imageUrl: 'https://i.imgur.com/wnQBodT.png'),
      Mv2Emoji('[歪嘴]', imageUrl: 'https://i.imgur.com/84ycU43.png'),
      Mv2Emoji('[调皮]', imageUrl: 'https://i.imgur.com/ggHTLzH.png'),
      Mv2Emoji('[笑哭]', imageUrl: 'https://i.imgur.com/h8edr5G.png'),
      Mv2Emoji('[嗑瓜子]', imageUrl: 'https://i.imgur.com/GMzq0tq.png'),
      Mv2Emoji('[喜极而泣]', imageUrl: 'https://i.imgur.com/L1N27tb.png'),
      Mv2Emoji('[惊讶]', imageUrl: 'https://i.imgur.com/cuzxGOI.png'),
      Mv2Emoji('[给心心]', imageUrl: 'https://i.imgur.com/q663Mor.png'),
      Mv2Emoji('[呆]', imageUrl: 'https://i.imgur.com/xMXlmxm.png'),
      Mv2Emoji('[跪了]', imageUrl: 'https://i.imgur.com/0pjsMf0.png'),
      Mv2Emoji('[响指]', imageUrl: 'https://i.imgur.com/nkoevMu.png'),
      Mv2Emoji('[哇R]', imageUrl: 'https://i.imgur.com/ngoi2I6.png'),
      Mv2Emoji('[萌萌哒R]', imageUrl: 'https://i.imgur.com/vOHzwus.png'),
      Mv2Emoji('[害羞R]', imageUrl: 'https://i.imgur.com/1PeoVR5.png'),
      Mv2Emoji('[偷笑R]', imageUrl: 'https://i.imgur.com/WneGpK9.png'),
      Mv2Emoji('[哭惹R]', imageUrl: 'https://i.imgur.com/0aOdQJd.png'),
      Mv2Emoji('[汗颜R]', imageUrl: 'https://i.imgur.com/O8alqc1.png'),
    ]),
    Mv2EmojiGroup('小黄脸', <Mv2Emoji>[
      Mv2Emoji('😀'),
      Mv2Emoji('😁'),
      Mv2Emoji('😂'),
      Mv2Emoji('🤣'),
      Mv2Emoji('😅'),
      Mv2Emoji('😊'),
      Mv2Emoji('😋'),
      Mv2Emoji('😘'),
      Mv2Emoji('🥰'),
      Mv2Emoji('😗'),
      Mv2Emoji('🤩'),
      Mv2Emoji('🤔'),
      Mv2Emoji('🤨'),
      Mv2Emoji('😐'),
      Mv2Emoji('😑'),
      Mv2Emoji('🙄'),
      Mv2Emoji('😏'),
      Mv2Emoji('😪'),
      Mv2Emoji('😫'),
      Mv2Emoji('🥱'),
      Mv2Emoji('😜'),
      Mv2Emoji('😒'),
      Mv2Emoji('😔'),
      Mv2Emoji('😨'),
      Mv2Emoji('😰'),
      Mv2Emoji('😱'),
      Mv2Emoji('🥵'),
      Mv2Emoji('😡'),
      Mv2Emoji('🥳'),
      Mv2Emoji('🥺'),
      Mv2Emoji('🤭'),
      Mv2Emoji('🧐'),
      Mv2Emoji('😎'),
      Mv2Emoji('🤓'),
      Mv2Emoji('😭'),
      Mv2Emoji('🤑'),
      Mv2Emoji('🤮'),
    ]),
    Mv2EmojiGroup('手势', <Mv2Emoji>[
      Mv2Emoji('🙋'),
      Mv2Emoji('🙎'),
      Mv2Emoji('🙅'),
      Mv2Emoji('🙇'),
      Mv2Emoji('🤷'),
      Mv2Emoji('🤏'),
      Mv2Emoji('👉'),
      Mv2Emoji('✌️'),
      Mv2Emoji('🤘'),
      Mv2Emoji('🤙'),
      Mv2Emoji('👌'),
      Mv2Emoji('🤌'),
      Mv2Emoji('👍'),
      Mv2Emoji('👎'),
      Mv2Emoji('👋'),
      Mv2Emoji('🤝'),
      Mv2Emoji('🙏'),
      Mv2Emoji('👏'),
    ]),
    Mv2EmojiGroup('庆祝', <Mv2Emoji>[
      Mv2Emoji('✨'),
      Mv2Emoji('🎉'),
      Mv2Emoji('🎊'),
    ]),
    Mv2EmojiGroup('其他', <Mv2Emoji>[
      Mv2Emoji('👻'),
      Mv2Emoji('🤡'),
      Mv2Emoji('🐔'),
      Mv2Emoji('👀'),
      Mv2Emoji('💩'),
      Mv2Emoji('🐴'),
      Mv2Emoji('🦄'),
      Mv2Emoji('🐧'),
      Mv2Emoji('🐶'),
      Mv2Emoji('🐒'),
      Mv2Emoji('🙈'),
      Mv2Emoji('🙉'),
      Mv2Emoji('🙊'),
      Mv2Emoji('🐵'),
    ]),
  ];

  /// Token → low-definition image URL, inserted on submit.
  static const Map<String, String> _submitLinks = <String, String>{
    '[脱单doge]': 'https://i.imgur.com/L62ZP7V.png',
    '[doge]': 'https://i.imgur.com/agAJ0Rd.png',
    '[辣眼睛]': 'https://i.imgur.com/n119Wvk.png',
    '[疑惑]': 'https://i.imgur.com/U3hKhrT.png',
    '[捂脸]': 'https://i.imgur.com/14cwgsI.png',
    '[哦呼]': 'https://i.imgur.com/km62MY2.png',
    '[傲娇]': 'https://i.imgur.com/TkdeN49.png',
    '[思考]': 'https://i.imgur.com/MAyk5GN.png',
    '[吃瓜]': 'https://i.imgur.com/Ug1iMq4.png',
    '[无语]': 'https://i.imgur.com/e1q9ScT.png',
    '[大哭]': 'https://i.imgur.com/YGIx7lh.png',
    '[酸了]': 'https://i.imgur.com/5FDsp6L.png',
    '[打call]': 'https://i.imgur.com/pmNOo2w.png',
    '[歪嘴]': 'https://i.imgur.com/XzEYBoY.png',
    '[星星眼]': 'https://i.imgur.com/2spsghH.png',
    '[OK]': 'https://i.imgur.com/6DMydmQ.png',
    '[跪了]': 'https://i.imgur.com/TYtySHv.png',
    '[响指]': 'https://i.imgur.com/Ac88cMm.png',
    '[调皮]': 'https://i.imgur.com/O6ZZSLk.png',
    '[笑哭]': 'https://i.imgur.com/NIvxivj.png',
    '[嗑瓜子]': 'https://i.imgur.com/rjR4rdr.png',
    '[喜极而泣]': 'https://i.imgur.com/N9E3iZ2.png',
    '[惊讶]': 'https://i.imgur.com/aptfuiN.png',
    '[给心心]': 'https://i.imgur.com/4aXVwxJ.png',
    '[呆]': 'https://i.imgur.com/c1Q76Cd.png',
    '[哭惹R]': 'https://i.imgur.com/HgxsUD2.png',
    '[哇R]': 'https://i.imgur.com/OZySWIG.png',
    '[汗颜R]': 'https://i.imgur.com/jrVZoLi.png',
    '[害羞R]': 'https://i.imgur.com/OVQjxIr.png',
    '[萌萌哒R]': 'https://i.imgur.com/Ue1kikn.png',
    '[偷笑R]': 'https://i.imgur.com/aF7QiE5.png',
  };

  static final RegExp _tokenPattern = RegExp(r'\[[^\]]+\]');

  /// Mirrors V2EX Polish's `transformEmoji`: known `[token]`s become the hosted
  /// image URL (plus a trailing space) so V2EX embeds them; unknown bracketed
  /// text is left untouched.
  static String expandForSubmit(String text) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(_tokenPattern, (Match match) {
      final url = _submitLinks[match.group(0)];
      return url == null ? match.group(0)! : '$url ';
    });
  }

  /// Flattened token list, handy for tests.
  static Iterable<String> get allTokens =>
      groups.expand((Mv2EmojiGroup group) => group.emoji.map((e) => e.token));
}
