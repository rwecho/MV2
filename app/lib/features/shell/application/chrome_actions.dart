import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/mv2_floating_tab_bar.dart';

/// How many page actions the rail shows at once.
///
/// The folded cover display's strip is ~470pt tall and the five destinations
/// already take ~275pt of it, so three action tiles are the budget that always
/// fits without scrolling.
const int maxToolbarActions = 3;

/// One action the current page contributes to the Duo's trailing rail.
///
/// Apple's iPhone Duo guidance puts the toolbar and the tab bar in the same
/// edge strip ("Designing for iPhone Duo"), so page-level actions belong there
/// too — this is the trailing half of that idea.
@immutable
class Mv2ToolbarAction {
  const Mv2ToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.activeIcon,
    this.active = false,
  });

  /// Icon shown while [active] is false.
  final IconData icon;

  /// Icon shown while [active] is true (e.g. 已收藏 / 已感谢).
  final IconData? activeIcon;

  final String label;

  /// Same callback as the on-page button, so behaviour cannot drift.
  final VoidCallback onTap;

  final bool active;

  /// Identity for change detection: labels/icons/active state only. The
  /// callbacks are rebuilt with the page, so comparing them would rebuild the
  /// rail on every frame.
  bool sameAs(Mv2ToolbarAction other) =>
      other.icon == icon &&
      other.activeIcon == activeIcon &&
      other.label == label &&
      other.active == active;
}

/// Context chrome for the trailing rail: what the page currently on screen
/// offers in that strip. `null` or empty means "no page actions", and the rail
/// falls back to its default 搜索 / 账号 pair.
///
/// Pages publish here because the rail is window chrome owned by the shell,
/// while the actions and their state live with the page (same sign-in guards,
/// same toasts, same optimistic flags).
class Mv2ToolbarActionsController extends Notifier<List<Mv2ToolbarAction>?> {
  @override
  List<Mv2ToolbarAction>? build() => null;

  void set(List<Mv2ToolbarAction>? actions) {
    if (_sameAs(state, actions)) return;
    state = actions;
  }

  void clear() => set(null);

  bool _sameAs(List<Mv2ToolbarAction>? a, List<Mv2ToolbarAction>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].sameAs(b[i])) return false;
    }
    return true;
  }
}

final toolbarActionsProvider =
    NotifierProvider<Mv2ToolbarActionsController, List<Mv2ToolbarAction>?>(
      Mv2ToolbarActionsController.new,
    );

/// Destination the trailing tab bar highlights.
///
/// The shell owns the branch index (and its navigator state), while the tab bar
/// now lives in window chrome above the router, so the shell publishes the
/// current destination here whenever it changes.
class ShellTabController extends Notifier<Mv2Tab> {
  @override
  Mv2Tab build() => Mv2Tab.feed;

  void select(Mv2Tab tab) {
    if (tab != state) state = tab;
  }
}

final shellTabProvider = NotifierProvider<ShellTabController, Mv2Tab>(
  ShellTabController.new,
);
