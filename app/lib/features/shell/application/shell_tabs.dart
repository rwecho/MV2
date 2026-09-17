import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../../../ui/components/mv2_floating_tab_bar.dart';
import '../../../ui/mv2_haptics.dart';
import '../../composer/presentation/composer_sheets.dart';
import '../../settings/application/settings_controller.dart';
import 'shell_chrome.dart';

/// Switches the shell to [tab] the same way a tap on the floating bar does:
/// haptics, `tab_switch` attribution, chrome reset, then the branch switch.
///
/// Single choke point for **programmatic** tab switches (the header account
/// avatar is one), so they stay indistinguishable from a real tab tap. 发布 is
/// an action rather than a branch and opens the composer instead.
///
/// [shell] must be given by callers that are *not* below the shell in the
/// widget tree — the floating bar itself is a sibling of it. Widgets inside a
/// branch (the avatar) omit it and the switch goes through `go()`, which
/// StatefulShellRoute resolves to the same branch switch (go_router 18 does
/// not export the shell state type, so `goBranch` is unreachable from here).
void selectShellTab(
  BuildContext context,
  WidgetRef ref,
  Mv2Tab tab, {
  StatefulNavigationShell? shell,
}) {
  // Entering a branch always shows the chrome again, even if the previous
  // branch was scrolled far enough to hide the bar.
  ref.read(shellBarCollapsedProvider.notifier).reset();
  // 设置 → 触觉反馈.
  Mv2Haptics.tap(ref.read(settingsProvider).hapticsEnabled);

  if (tab == Mv2Tab.publish) {
    // 发布是动作不是分支;打开入口归 publish_open(默认 source: tab)。
    showPublishComposer(context);
    return;
  }

  Mv2Analytics.logTabSwitch(tab: tab.name);

  if (shell != null) {
    final index = switch (tab) {
      Mv2Tab.feed => 0,
      Mv2Tab.nodes => 1,
      Mv2Tab.notifications => 2,
      _ => 3,
    };
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
    return;
  }

  context.go(switch (tab) {
    Mv2Tab.feed => '/feed',
    Mv2Tab.nodes => '/nodes',
    Mv2Tab.notifications => '/notifications',
    _ => '/profile',
  });
}
