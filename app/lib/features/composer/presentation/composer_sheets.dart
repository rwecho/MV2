import 'package:flutter/widgets.dart';

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
Future<void> showPublishComposer(BuildContext context, {String? initialNode}) {
  return showMv2Sheet<void>(
    context,
    child: PublishTopicPage(initialNode: initialNode),
  );
}
