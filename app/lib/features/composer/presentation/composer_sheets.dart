import 'package:flutter/widgets.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../../../shared/models/models.dart';
import '../../../ui/components/mv2_modal_sheet.dart';
import 'publish_topic_page.dart';
import 'reply_composer_page.dart';

/// Opens the reply editor as a near-fullscreen modal sheet.
Future<void> showReplyComposer(
  BuildContext context, {
  required int topicId,
  int? floor,
  V2Reply? quotedReply,
  String? initialText,
}) {
  return showMv2Sheet<void>(
    context,
    child: ReplyComposerPage(
      topicId: topicId,
      floor: floor,
      quotedReply: quotedReply,
      initialText: initialText,
    ),
  );
}

/// Opens the 发布主题 form as a near-fullscreen modal sheet.
///
/// [source] 归因打开入口:tab(壳上的发布按钮,默认)|quick_action(iOS 主屏
/// 快捷方式)。composer 不是路由,screen_view 看不到它,这里是唯一计数点。
Future<void> showPublishComposer(
  BuildContext context, {
  String? initialNode,
  String source = 'tab',
}) {
  Mv2Analytics.logPublishOpen(source: source);
  return showMv2Sheet<void>(
    context,
    child: PublishTopicPage(initialNode: initialNode),
  );
}
