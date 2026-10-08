import 'package:flutter/material.dart';

import '../../core/native/mv2_native_bridge.dart';
import 'mv2_breakpoints.dart';

/// Keeps [mv2HorizontalSizeClass] in step with the folding state of the
/// device.
///
/// UIKit reports the *current* trait on demand; there is no push event for
/// `horizontalSizeClass` on the Flutter side, so this widget re-queries the
/// bridge whenever the window width crosses one of the layout breakpoints —
/// exactly the moment folding/unfolding changes the layout class (iPhone Duo
/// 386 ↔ 871wt). A re-sync that yields a different trait triggers a rebuild
/// so the shell can switch panes.
///
/// Pure width changes within a single bucket (e.g. keyboard insets) do not
/// re-query: the trait cannot change without crossing the floor/ceiling.
class Mv2SizeClassSync extends StatefulWidget {
  const Mv2SizeClassSync({required this.child, super.key});

  final Widget child;

  @override
  State<Mv2SizeClassSync> createState() => _Mv2SizeClassSyncState();
}

class _Mv2SizeClassSyncState extends State<Mv2SizeClassSync> {
  static const _bridge = Mv2NativeBridge();

  /// Width bucket of the last build: 0 = < duoExpandedBreakpoint,
  /// 1 = [duoExpandedBreakpoint, twoPaneBreakpoint), 2 = >= twoPaneBreakpoint.
  /// `null` means "never synced".
  int? _lastBucket;

  int _bucketFor(double width) {
    if (width >= twoPaneBreakpoint) return 2;
    if (width >= duoExpandedBreakpoint) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final bucket = _bucketFor(width);
    if (bucket != _lastBucket) {
      _lastBucket = bucket;
      _sync();
    }
    return widget.child;
  }

  Future<void> _sync() async {
    final trait = await _bridge.horizontalSizeClass();
    if (!mounted) return;
    if (trait != mv2HorizontalSizeClass) {
      mv2HorizontalSizeClass = trait;
      // New trait may have flipped mv2IsTwoPane; rebuild to re-evaluate.
      setState(() {});
    }
  }
}