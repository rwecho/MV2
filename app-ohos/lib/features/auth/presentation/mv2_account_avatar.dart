import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../../../ui/primitives/mv2_avatar.dart';

/// The header avatar on the four primary pages.
///
/// Shows the signed-in member's avatar, and a neutral placeholder while signed
/// out — a placeholder account's photo must never be shown to an anonymous
/// user (the mock fixtures used to leak one into the header).
class Mv2AccountAvatar extends ConsumerWidget {
  const Mv2AccountAvatar({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value?.user;

    if (user != null) {
      return Mv2Avatar(user: user, size: size, showBorder: true);
    }

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
