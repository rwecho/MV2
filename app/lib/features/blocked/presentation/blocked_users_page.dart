import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_settings_row.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../library/presentation/confirm_dialog.dart';
import '../application/blocked_users_controller.dart';

/// 屏蔽用户 — secondary page listing the locally blocked usernames.
///
/// Blocking is a local preference: nothing is sent to V2EX, so the list only
/// ever contains names the user blocked on this device.
class BlockedUsersPage extends ConsumerWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);
    final usernames = blocked.toList()..sort();
    final bottomInset = Mv2PageScaffold.bottomContentInset(context);

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(
        title: '屏蔽用户',
        onBack: () => context.pop(),
        actions: <Widget>[
          Mv2IconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: '全部解除',
            onPressed: usernames.isEmpty ? null : () => _clear(context, ref),
          ),
        ],
      ),
      child: usernames.isEmpty
          ? const Mv2StateView(
              kind: Mv2StateKind.empty,
              title: '还没有屏蔽的用户',
              description: '在主题或回复中屏蔽用户后，会出现在这里。',
            )
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                Mv2Spacing.pageNarrow,
                0,
                Mv2Spacing.pageNarrow,
                bottomInset,
              ),
              child: Mv2SettingsGroup(
                topGap: Mv2Spacing.x4,
                children: <Widget>[
                  for (int i = 0; i < usernames.length; i++)
                    Mv2SettingsRow(
                      label: usernames[i],
                      icon: Icons.person_off_outlined,
                      showChevron: false,
                      showDivider: i < usernames.length - 1,
                      trailing: Mv2TextButton(
                        label: '解除',
                        onPressed: () {
                          Mv2Analytics.logBlockedUnblock(count: 1);
                          ref
                              .read(blockedUsersProvider.notifier)
                              .unblock(usernames[i]);
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '全部解除',
      message: '将解除屏蔽全部用户，确定继续吗？',
      confirmLabel: '解除',
    );
    if (!confirmed || !context.mounted) return;
    // build 里的 usernames 局部变量在此不可见,重新读一份计数。
    Mv2Analytics.logBlockedUnblock(count: ref.read(blockedUsersProvider).length);
    await ref.read(blockedUsersProvider.notifier).clear();
  }
}
