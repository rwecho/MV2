import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ui/utils/mv2_breakpoints.dart';
import '../../../ui/utils/mv2_sheet_page.dart';
import '../../shell/application/tablet_topic_pane.dart';

/// Opens a topic the way the current window shape wants: into the tablet's
/// right-hand detail pane on wide viewports, or as the usual full-screen
/// `/topic/:id` push on phones.
///
/// Deliberately ref-free (reads the provider container from [context]) —
/// several call sites live inside plain StatelessWidgets, and the publish
/// flow needs to work across a `router.pop()`, which the root container
/// outlives.
void openTopic(BuildContext context, int topicId, {int? floor}) {
  if (mv2IsTwoPane(context)) {
    ProviderScope.containerOf(context, listen: false)
        .read(tabletTopicPaneProvider.notifier)
        .open(topicId, floor);
    // If the call came from a sheet card (用户主页, 我的主题, 历史, …), the
    // topic now shows in the shell's pane behind it — close the card to
    // reveal it. From the left-pane lists the enclosing route is the shell
    // page itself, whose location is not a sheet location, so nothing pops.
    // `canPop` guards the cold-started deep link where the card *is* the base
    // route and there is nothing beneath it.
    final route = ModalRoute.of(context);
    if (mv2IsSheetLocation(route?.settings.name) && context.canPop()) {
      context.pop();
    }
    return;
  }
  context.push('/topic/$topicId${floor != null ? '?floor=$floor' : ''}');
}
