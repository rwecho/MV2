import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:foldable/foldable.dart';

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

  /// Last fold snapshot written to the log, so diagnostics stay one line per
  /// change instead of one per frame.
  String? _loggedFold;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size != _lastSize) {
      _lastSize = size;
      _sync();
    }
    if (kDebugMode) _logFold(context);
    return widget.child;
  }

  /// Debug diagnostics: what UIKit reports about the fold, so the chrome's
  /// geometry can be checked against the device rather than guessed.
  void _logFold(BuildContext context) {
    final data = DuoMediaQuery.maybeOf(context);
    if (data == null) return;
    final regions = data.regions
        .map(
          (ReservedRegion r) =>
              '${r.kind.wireName}${r.bounds}${r.isActive ? '' : '(inactive)'}',
        )
        .join(' | ');
    final line =
        'MV2: fold status=${data.status.name} '
        'angle=${data.angleDegrees?.toStringAsFixed(1)} '
        'sizeClass=${data.horizontalSizeClass.name} '
        'regions=[$regions]';
    if (line == _loggedFold) return;
    _loggedFold = line;
    debugPrint(line);
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
