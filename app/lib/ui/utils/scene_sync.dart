import 'package:flutter/material.dart';

import '../../core/native/mv2_native_bridge.dart';
import '../utils/mv2_breakpoints.dart';
import '../utils/scene_geometry.dart';

/// Keeps [mv2HorizontalSizeClass] and [mv2SceneGeometry] in step with the
/// device.
///
/// UIKit reports the current trait and scene geometry on demand; there is no
/// push event for either on the Flutter side, so this widget re-queries the
/// bridge whenever the window size changes — exactly the moment folding,
/// unfolding or rotation changes the trait, the safe area and the strip the
/// system keeps for its own chrome on the Duo. A re-sync that yields a different
/// value triggers a rebuild so the shell can re-evaluate [mv2IsTwoPane] and
/// [mv2UsesTrailingRail].
class Mv2SceneSync extends StatefulWidget {
  const Mv2SceneSync({required this.child, super.key});

  final Widget child;

  @override
  State<Mv2SceneSync> createState() => _Mv2SceneSyncState();
}

class _Mv2SceneSyncState extends State<Mv2SceneSync> {
  static const _bridge = Mv2NativeBridge();

  /// Last window size we queried for; `null` means "never synced".
  Size? _lastSize;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size != _lastSize) {
      _lastSize = size;
      _sync();
    }
    return widget.child;
  }

  Future<void> _sync() async {
    final trait = await _bridge.horizontalSizeClass();
    final rawGeometry = await _bridge.uiGeometry();
    if (!mounted) return;
    final geometry = Mv2SceneGeometry.fromMap(rawGeometry);
    final traitChanged = trait != mv2HorizontalSizeClass;
    final geometryChanged = geometry != mv2SceneGeometry;
    if (!traitChanged && !geometryChanged) return;
    mv2HorizontalSizeClass = trait;
    mv2SceneGeometry = geometry;
    // The new values may have flipped the two-pane layout or the trailing rail;
    // rebuild to re-evaluate.
    setState(() {});
  }
}
