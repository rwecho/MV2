import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The topic currently shown in the tablet's right-hand detail pane.
///
/// `null` means no topic is open and the pane shows its empty state.
/// Only written on wide viewports (`mv2IsTwoPane`) — phones keep pushing the
/// full-screen `/topic/:id` route.
class TabletTopicPaneState {
  const TabletTopicPaneState({required this.topicId, this.floor});

  final int topicId;

  /// Reply floor to scroll to, mirroring `/topic/123?floor=4`.
  final int? floor;
}

class TabletTopicPaneController extends Notifier<TabletTopicPaneState?> {
  @override
  TabletTopicPaneState? build() => null;

  void open(int topicId, int? floor) {
    state = TabletTopicPaneState(topicId: topicId, floor: floor);
  }

  void close() => state = null;
}

final tabletTopicPaneProvider =
    NotifierProvider<TabletTopicPaneController, TabletTopicPaneState?>(
      TabletTopicPaneController.new,
    );
