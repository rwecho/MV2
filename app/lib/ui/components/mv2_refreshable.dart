import 'package:flutter/material.dart';

import '../../design_system/theme/mv2_theme.dart';
import 'mv2_error_feedback.dart';

/// MV2 pull-to-refresh wrapper.
///
/// Centralises the accent spinner so every data list refreshes consistently,
/// and toasts the failure when the refresh future throws (so a failed refresh
/// is never silent while stale data stays on screen). The child scrollable must
/// use [AlwaysScrollableScrollPhysics] (or be wrapped with
/// [Mv2RefreshableFill]) so a list shorter than the viewport can still be
/// pulled down.
class Mv2Refreshable extends StatelessWidget {
  const Mv2Refreshable({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  Future<void> _refresh(BuildContext context) async {
    try {
      await onRefresh();
    } catch (error) {
      if (!context.mounted) return;
      mv2ShowError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      color: colors.accent,
      backgroundColor: colors.surface,
      child: child,
    );
  }
}

/// Keeps pull-to-refresh working for empty / error placeholders: the [child] is
/// centred inside a viewport-filling, always-scrollable box.
class Mv2RefreshableFill extends StatelessWidget {
  const Mv2RefreshableFill({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Mv2Refreshable(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ),
      ),
    );
  }
}
