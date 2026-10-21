import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Stateful scroll rule shared by pages that collapse chrome while reading.
///
/// A brief counter-scroll should not immediately reopen/close the chrome. Keep
/// a running distance in the current direction and switch only after the user
/// has moved far enough. Reaching the top always expands immediately. Nested
/// vertical scrollables do not control the page chrome.
class Mv2ScrollCollapseController {
  Mv2ScrollCollapseController({
    this.collapseDistance = 28,
    this.expandDistance = 20,
    this.maxNotificationDepth = 0,
  });

  final double collapseDistance;
  final double expandDistance;
  final int maxNotificationDepth;

  double _distance = 0;
  ScrollDirection _direction = ScrollDirection.idle;

  /// Returns the new collapsed state, or null when it has not changed.
  bool? handle(ScrollNotification notification, {required bool isCollapsed}) {
    if (notification.metrics.axis != Axis.vertical ||
        notification.depth > maxNotificationDepth) {
      return null;
    }

    if (notification.metrics.pixels <= 0) {
      _reset();
      return isCollapsed ? false : null;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.idle) {
        _reset();
        return null;
      }
      if (notification.direction != _direction) {
        _direction = notification.direction;
        _distance = 0;
      }
      return null;
    }

    if (notification is! ScrollUpdateNotification ||
        notification.dragDetails == null) {
      return null;
    }

    final delta = notification.scrollDelta ?? 0;
    if (delta.abs() < _deltaSlop) return null;
    final direction = delta > 0
        ? ScrollDirection.reverse
        : ScrollDirection.forward;
    if (direction != _direction) {
      _direction = direction;
      _distance = 0;
    }
    _distance += delta.abs();

    if (!isCollapsed &&
        direction == ScrollDirection.reverse &&
        notification.metrics.pixels > _topSlop &&
        _distance >= collapseDistance) {
      _distance = 0;
      return true;
    }
    if (isCollapsed &&
        direction == ScrollDirection.forward &&
        _distance >= expandDistance) {
      _distance = 0;
      return false;
    }
    return null;
  }

  void _reset() {
    _distance = 0;
    _direction = ScrollDirection.idle;
  }
}

const double _topSlop = 8;
const double _deltaSlop = 1;
