import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../ui/components/mv2_floating_tab_bar.dart';
import '../../../../ui/primitives/mv2_avatar.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../shell/application/shell_tabs.dart';

/// The header avatar on the four primary pages.
///
/// Shows the signed-in member's avatar, and a neutral placeholder while signed
/// out — a placeholder account's photo must never be shown to an anonymous
/// user (the mock fixtures used to leak one into the header).
///
/// Tapping it is the header shortcut every other client has: signed in it
/// switches to the 我的 tab, signed out it opens the login sheet.
class Mv2AccountAvatar extends ConsumerWidget {
  const Mv2AccountAvatar({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value?.user;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (user != null) {
          selectShellTab(context, ref, Mv2Tab.profile);
          return;
        }
        context.push('/login');
      },
      child: user != null
          ? Mv2Avatar(user: user, size: size, showBorder: true)
          : _Placeholder(size: size),
    );
  }
}

/// Neutral signed-out stand-in for the member's photo.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.divider,
        shape: BoxShape.circle,
        border: Border.all(color: colors.border),
      ),
      child: Icon(
        Icons.person_outline_rounded,
        size: size * 0.55,
        color: colors.textTertiary,
      ),
    );
  }
}
