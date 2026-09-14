import 'package:flutter/material.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';

/// MV2 near-fullscreen modal sheet.
///
/// Used by the reply editor and the 发布主题 form: they are lightweight,
/// frequent flows that read better as a sheet — the surface behind stays
/// visible, the top is rounded, and a drag (or a scrim tap / back gesture)
/// dismisses them. The page inside keeps its own [Scaffold], whose
/// `resizeToAvoidBottomInset` lifts the pinned footer for the keyboard.
///
/// Returns the value passed to `Navigator.pop`, if any.
Future<T?> showMv2Sheet<T>(
  BuildContext context, {
  required Widget child,
  double heightFactor = 0.92,
}) {
  final colors = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: colors.scrim,
    // The sheet is positioned by its own container; the page handles the rest.
    useSafeArea: false,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Mv2Radius.xlValue),
        ),
        child: Container(
          height: media.size.height * heightFactor,
          color: colors.background,
          child: Column(
            children: <Widget>[
              const _SheetGrabber(),
              Expanded(
                // The sheet already sits below the status bar, so the page's
                // own `SafeArea`/`Scaffold` must not add the top inset again.
                child: MediaQuery.removePadding(
                  context: sheetContext,
                  removeTop: true,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Grabber bar that advertises the drag-to-dismiss affordance.
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: Mv2Spacing.x5,
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: colors.border,
            borderRadius: Mv2Radius.pill,
          ),
        ),
      ),
    );
  }
}
