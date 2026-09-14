import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/provider_retry.dart';
import '../../../shared/models/topic_detail.dart';
import '../../library/application/library_providers.dart';

/// Topic detail request key: replies are paginated, so the page is part of the
/// cache identity.
class TopicDetailArgs {
  const TopicDetailArgs(this.topicId, {this.page = 1});

  final int topicId;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is TopicDetailArgs &&
      other.topicId == topicId &&
      other.page == page;

  @override
  int get hashCode => Object.hash(topicId, page);
}

final topicDetailProvider =
    FutureProvider.family<V2TopicDetail, TopicDetailArgs>((ref, args) async {
      final detail = await ref
          .watch(v2exApiProvider)
          .topicDetail(args.topicId, page: args.page);

      // Record every successful first-page load into 浏览历史. Fire-and-forget:
      // `recordHistory` swallows storage errors, so a history failure can never
      // break the topic page. Only page 1 is recorded (paging re-reads the topic).
      if (args.page == 1 && ref.mounted) {
        unawaited(
          ref.read(libraryControllerProvider).recordHistory(detail.topic),
        );
      }

      return detail;
    }, retry: mv2Retry);
