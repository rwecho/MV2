import 'package:flutter/material.dart';

/// Window width (logical px) at which the app switches to the tablet
/// two-pane layout: topic lists stay on the left and the opened topic opens
/// in a right-hand pane instead of pushing a full-screen route.
///
/// Covers every iPad in landscape and the 13" models in portrait; the mini
/// and 11" models in portrait (744 / 834) stay single-column.
const double twoPaneBreakpoint = 900.0;

/// Foldable-expanded floor (logical px): iPhone Duo's unfolded inner display
/// (871) is narrower than the iPad breakpoint, so [mv2IsTwoPane] additionally
/// accepts widths in `[duoExpandedBreakpoint, twoPaneBreakpoint)` **when the
/// UIKit trait is regular**. The floor sits between the iPad 11" portrait
/// (834) and Duo unfolded (871) so plain iPad portrait stays single-column.
const double duoExpandedBreakpoint = 850.0;

/// The last UIKit `horizontalSizeClass` bridge value ("compact"/"regular").
///
/// `null` until the native bridge answers (non-iOS or before first sync); in
/// that state the layout is decided purely by [twoPaneBreakpoint] so Android
/// / desktop / tests behave exactly as before. This is deliberately a simple
/// module-level cache: a single mutable global backed by one async read at
/// startup plus a re-read whenever the window size crosses a breakpoint.
String? mv2HorizontalSizeClass;

/// Whether the current window is wide enough for the two-pane layout.
bool mv2IsTwoPane(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= twoPaneBreakpoint) return true;
  // iPhone Duo unfolded (871pt) is narrower than 900, but its inner display
  // reports a regular-width trait. Plain iPhones (even landscape, ~874pt)
  // are always compact, so this cannot leak the phone layout to Duo and vice
  // versa. iPad portrait widths (744 / 834) are regular too, so guard with
  // the explicit floor.
  return mv2HorizontalSizeClass == 'regular' && w >= duoExpandedBreakpoint;
}

/// Trailing safe-area inset (logical px) that marks the unfolded Duo's
/// sensor-bar side. Measured on the unfolded inner display: 84pt, while the
/// leading side is 0 — every other supported device has a much smaller (or
/// symmetric) trailing inset.
const double trailingRailMinInset = 60.0;

/// Whether the shell should host its chrome in a vertical trailing rail.
///
/// Only the unfolded iPhone Duo in landscape qualifies: a **regular-width**
/// window (so a phone in landscape, always compact, can never match) carrying a
/// trailing safe-area strip wider than its leading one. That strip is where iOS
/// itself parks the status bar and the Dynamic Island, and it is otherwise dead
/// space — so moving 首页/节点/发布/通知/我的 plus the page actions into it costs
/// no content width and frees the bottom bar's height (Apple HIG: "Designing
/// for iPhone Duo").
///
/// Phones (compact) and iPads (symmetric insets) keep the floating bottom bar.
bool mv2UsesTrailingRail(BuildContext context) {
  final padding = MediaQuery.paddingOf(context);
  final width = MediaQuery.sizeOf(context).width;
  return mv2HorizontalSizeClass == 'regular' &&
      width >= duoExpandedBreakpoint &&
      padding.right >= trailingRailMinInset &&
      padding.right > padding.left;
}