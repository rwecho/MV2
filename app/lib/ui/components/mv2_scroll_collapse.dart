import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Shared scroll rule for the collapsing page chrome.
///
/// Scrolling toward the end of the list (reading down) collapses the page
/// header / bottom bars; scrolling back expands them again. Returns `null` when
/// the notification should leave the current state untouched, so callers can
/// ignore horizontal (PageView) scrolls and idle/overscroll events.
///
/// [ScrollNotification.metrics] `axis` gates the horizontal `PageView` in the
/// home feed: only the inner vertical lists drive the chrome.
bool? mv2CollapseFromScroll(ScrollNotification notification) {
  if (notification.metrics.axis != Axis.vertical) return null;

  // The list is back at its very top: always expand, even mid-fling.
  if (notification.metrics.pixels <= 0) return false;

  if (notification is UserScrollNotification) {
    return switch (notification.direction) {
      // Reading on — collapse once we are past a small slop so a tiny nudge at
      // the top does not hide the header.
      ScrollDirection.reverse => notification.metrics.pixels > _slop,
      ScrollDirection.forward => false,
      ScrollDirection.idle => null,
    };
  }

  // Raw finger deltas keep the rule working for programmatic/one-shot drags
  // that do not emit a direction change. Gated on [dragDetails] so a fling's
  // ballistic bounce cannot flip the chrome back and forth.
  if (notification is ScrollUpdateNotification &&
      notification.dragDetails != null) {
    final delta = notification.scrollDelta ?? 0;
    if (delta > _deltaSlop) return true;
    if (delta < -_deltaSlop) return false;
  }
  return null;
}

/// Ignore reverse direction within the first few pixels of travel.
const double _slop = 8;

/// Minimum per-frame delta before a raw scroll update flips the chrome.
const double _deltaSlop = 1;
