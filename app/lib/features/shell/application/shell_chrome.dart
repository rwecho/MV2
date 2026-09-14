import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the floating bottom bar is hidden because the user is scrolling
/// through content.
///
/// Scrollable branches (the home feed) drive this from their scroll direction
/// so the bar slides away while reading and returns on scroll-back, matching
/// the collapsing top header. Branch switches reset it, so every tab opens with
/// its chrome visible.
class ShellBarCollapseController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool collapsed) {
    if (state != collapsed) state = collapsed;
  }

  void reset() => set(false);
}

final shellBarCollapsedProvider =
    NotifierProvider<ShellBarCollapseController, bool>(
      ShellBarCollapseController.new,
    );
