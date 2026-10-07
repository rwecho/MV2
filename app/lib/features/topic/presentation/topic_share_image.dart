import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/parser/html_dom.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/models/topic_detail.dart';
import '../../../ui/components/mv2_rich_text.dart';

/// 一键生成主题分享长图（V2EX Polish 同款）：把主题渲染成一张固定宽度的
/// 浅色长图，经系统分享面板发出。聊天窗口里深色图不可读，分享图永远用
/// 浅色主题渲染，与 app 当前主题无关。
///
/// 截图走根 Overlay：挂一个移出屏幕的 [RepaintBoundary]，等两帧（build/
/// layout + paint 落层）后 `toImage`。不用 Offstage/Opacity(0) —— 两者都
/// 会跳过绘制，截出来是空白。
Future<bool> shareTopicAsImage(
  BuildContext context,
  V2TopicDetail detail,
) async {
  // Overlay 与锚点都在进异步前取好，避免拿着调用方的 context 跨间隙。
  final overlay = Overlay.of(context, rootOverlay: true);
  final box = context.findRenderObject() as RenderBox?;
  final origin = (box != null && box.hasSize)
      ? box.localToGlobal(Offset.zero) & box.size
      : null;

  // 正文图片先预热缓存，截到占位灰块的图没有分享价值。整体限时长，慢图
  // 宁可缺席也不拖住分享。
  await _precacheContentImages(context, detail.contentHtml);

  final boundaryKey = GlobalKey();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => IgnorePointer(
      child: Transform.translate(
        // 移出可视区但仍在绘制树里。
        offset: const Offset(-10000, -10000),
        child: RepaintBoundary(
          key: boundaryKey,
          child: Theme(
            data: Mv2ThemeData.light(),
            child: TopicShareCard(detail: detail),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final renderContext = boundaryKey.currentContext;
    if (renderContext == null || !renderContext.mounted) return false;
    final boundary =
        renderContext.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize || boundary.size.isEmpty) {
      return false;
    }
    final size = boundary.size;
    // 长图高度不受限；超出常见 GPU 纹理上限（8192px）时整体压 pixelRatio，
    // 宁可糊一点也不能让 toImage 直接失败。
    final pixelRatio = (8192 / (size.width > size.height
        ? size.width
        : size.height)).clamp(1.0, 3.0);
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return false;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/mv2_share_topic_${detail.topic.id}.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

    final topic = detail.topic;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: '${topic.title}  ${topic.url ?? 'https://www.v2ex.com/t/${topic.id}'}',
        sharePositionOrigin: origin,
      ),
    );
    return true;
  } catch (error, stackTrace) {
    debugPrint('MV2: topic share image failed: $error\n$stackTrace');
    return false;
  } finally {
    entry.remove();
  }
}

/// 预热正文里的内容图（表情图不走这里——它们是行内小图，失败有 alt 兜底）。
Future<void> _precacheContentImages(
  BuildContext context,
  String? html,
) async {
  if (html == null || html.isEmpty) return;
  final sources = <String>[];
  void visit(dom.Node node) {
    if (node is dom.Element && node.localName == 'img') {
      final src = absoluteV2exUrl(node.attributes['src']);
      if (src != null) sources.add(src);
    }
    for (final child in node.nodes) {
      visit(child);
    }
  }

  visit(html_parser.parseFragment(html));
  if (sources.isEmpty) return;
  try {
    await Future.wait(<Future<void>>[
      for (final src in sources)
        precacheImage(CachedNetworkImageProvider(src), context).timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        ),
    ]);
  } catch (_) {
    // 单图预热失败不阻断分享——缺一张图好过分享不出来。
  }
}

/// 分享长图的版面：固定宽度、浅色底，内容按自然高度撑开（没有分页）。
/// 公开出来是为了 widget 测试能直接挂载它检查版面。
class TopicShareCard extends StatelessWidget {
  const TopicShareCard({super.key, required this.detail});

  final V2TopicDetail detail;

  /// 分享图在聊天窗口里的阅读宽度（逻辑像素）。
  static const double width = 375;

  @override
  Widget build(BuildContext context) {
    final topic = detail.topic;
    final link = topic.url ?? 'https://www.v2ex.com/t/${topic.id}';
    final contentHtml = detail.contentHtml;
    final body = topic.body;

    return Container(
      width: width,
      color: Colors.white,
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (topic.node.name.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x141B7A4B),
                    borderRadius: Mv2Radius.allXs,
                  ),
                  child: Text(
                    topic.node.name,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Color(0xFF1B7A4B),
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                topic.createdAtLabel,
                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
              ),
            ],
          ),
          const SizedBox(height: Mv2Spacing.x3),
          Text(
            topic.title,
            style: const TextStyle(
              fontSize: 20,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: Color(0xFF222222),
            ),
          ),
          const SizedBox(height: Mv2Spacing.x2),
          Text(
            '@${topic.author.username}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
          ),
          const SizedBox(height: Mv2Spacing.x3),
          if (contentHtml != null && contentHtml.isNotEmpty)
            Mv2RichText(
              html: contentHtml,
              baseStyle: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: Color(0xFF333333),
              ),
            )
          else if (body != null && body.isNotEmpty)
            Text(
              body.join('\n\n'),
              style: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: Color(0xFF333333),
              ),
            )
          else if ((topic.excerpt ?? '').isNotEmpty)
            Text(
              topic.excerpt!,
              style: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: Color(0xFF333333),
              ),
            ),
          const SizedBox(height: Mv2Spacing.x4),
          Text(
            '${topic.replyCount} 条回复'
            '${detail.statsLabel == null ? '' : '  ·  ${detail.statsLabel}'}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
          ),
          const SizedBox(height: Mv2Spacing.x2),
          Container(height: 1, color: const Color(0xFFEEEEEE)),
          const SizedBox(height: Mv2Spacing.x2),
          // 两行排，而不是挤在一个 Row 里——链接长短不可控，一行排必溢出。
          const Text(
            'MV2 · 更好的 V2EX 客户端',
            style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
          ),
          const SizedBox(height: 2),
          Text(
            link,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
          ),
        ],
      ),
    );
  }
}
