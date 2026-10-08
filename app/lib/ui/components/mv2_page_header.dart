import 'package:flutter/material.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_spacing.dart';

/// Page header used by the four primary pages
/// (`designs/01`, `04`, `06`, `07`): large title + subtitle + trailing actions.
class Mv2PageHeader extends StatelessWidget {
  const Mv2PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x2,
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: context.text.pageTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: context.text.metadata.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Secondary page header with a back affordance and centered title
/// (`designs/03-reply-composer.png`, `designs/08-settings.png`).
class Mv2SecondaryHeader extends StatelessWidget {
  const Mv2SecondaryHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const <Widget>[],
    this.leadingIcon = Icons.arrow_back_ios_new_rounded,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;

  /// Leading affordance; modal surfaces pass a close icon instead of a back
  /// chevron.
  final IconData leadingIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: 52,
      child: Stack(
        children: <Widget>[
          Align(
            alignment: Alignment.center,
            child: Text(
              title,
              style: context.text.itemTitle.copyWith(color: colors.textPrimary),
            ),
          ),
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: Mv2Spacing.x2),
                child: IconButton(
                  onPressed: onBack,
                  icon: Icon(leadingIcon, size: 18),
                  color: colors.textPrimary,
                  splashRadius: 22,
                ),
              ),
            ),
          if (actions.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: Mv2Spacing.x3),
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ),
        ],
      ),
    );
  }
}
