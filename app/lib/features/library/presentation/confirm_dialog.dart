import 'package:flutter/material.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';

/// Confirmation dialog shared by the local library pages.
///
/// Mirrors 设置 → 清除缓存's `_confirm` helper exactly (token colours, radius,
/// typography, `取消` + destructive confirm) so the two flows read as one app.
/// Resolves to `false` when the dialog is dismissed.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final colors = dialogContext.colors;
      return AlertDialog(
        backgroundColor: colors.elevatedSurface,
        shape: const RoundedRectangleBorder(borderRadius: Mv2Radius.allXl),
        title: Text(
          title,
          style: dialogContext.text.sectionTitle.copyWith(
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: dialogContext.text.bodySmall.copyWith(
            color: colors.textSecondary,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              '取消',
              style: dialogContext.text.button.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: dialogContext.text.button.copyWith(color: colors.danger),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
