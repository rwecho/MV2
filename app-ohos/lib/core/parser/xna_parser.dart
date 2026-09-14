import 'package:html/dom.dart';

import '../../shared/models/models.dart';
import 'html_dom.dart';

/// Parses V2EX's VXNA aggregator page (`/xna`) into [V2XnaEntry].
///
/// Verified against live markup (2026-09-11). VXNA shares the `#Tabs` row with
/// the topic tabs but renders its own item shape:
///
/// ```html
/// <div class="xna-entry cell">
///   <div class="xna-entry-avatar-container">
///     <a href="/member/arlmy"><img class="avatar" src="…"></a>
///   </div>
///   <div class="xna-entry-main-container">
///     <div class="xna-entry-title">
///       <a href="https://blog.example.com/post" class="topic-link" rel="ugc">标题</a>
///     </div>
///     <div class="xna-entry-info">
///       <span class="xna-entry-source"><a href="https://blog.example.com/" class="node">来源站</a></span>
///       <span class="xna-source-author"><a href="/member/arlmy">arlmy</a></span>
///       <span class="xna-entry-date">4 小时 0 分钟前</span>
///     </div>
///   </div>
/// </div>
/// ```
///
/// There is no on-site topic link and no reply count: the title is an external
/// URL, which is why VXNA gets its own model instead of reusing `V2Topic`.
abstract final class XnaParser {
  static List<V2XnaEntry> parse(String html) {
    final document = parseHtmlDocument(html);
    return document
        .querySelectorAll('div.xna-entry')
        .map(_parseEntry)
        .whereType<V2XnaEntry>()
        .toList(growable: false);
  }

  static V2XnaEntry? _parseEntry(Element item) {
    final titleAnchor = item.querySelector('.xna-entry-title a.topic-link');
    final title = cleanText(titleAnchor?.text);
    // XNA titles are absolute off-site URLs; the normaliser also tolerates
    // protocol-relative values without rewriting them into v2ex.com.
    final url = absoluteV2exUrl(titleAnchor?.attributes['href']);
    if (title == null || url == null) return null;

    final sourceAnchor = item.querySelector('.xna-entry-info a.node');
    final sourceName = cleanText(sourceAnchor?.text) ?? '未知来源';

    final authorAnchor = item.querySelector(
      '.xna-entry-info .xna-source-author a',
    );
    final authorName = cleanText(authorAnchor?.text);

    return V2XnaEntry(
      title: title,
      url: url,
      sourceName: sourceName,
      sourceUrl: absoluteV2exUrl(sourceAnchor?.attributes['href']),
      author: authorName == null
          ? null
          : V2User(
              username: authorName,
              avatarUrl: absoluteV2exUrl(item.attrOf('img.avatar', 'src')),
            ),
      timeLabel: cleanText(item.querySelector('.xna-entry-date')?.text),
    );
  }
}
