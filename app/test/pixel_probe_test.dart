import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Diagnostic helper (not a product test): prints pixel colours from a PNG so
/// screenshots can be compared against `designs/*.png` numerically.
///
/// Usage:
///   flutter test test/pixel_probe_test.dart \
///     --dart-define=PNG=/tmp/a.png --dart-define=POINTS="600,2400;20,100"
const _pngPath = String.fromEnvironment('PNG', defaultValue: '');

void main() {
  test('probe pixels', () async {
    const path = _pngPath;
    const pointsSpec = String.fromEnvironment('POINTS', defaultValue: '0,0');
    if (path.isEmpty) {
      // ignore: avoid_print
      print('PNG not provided');
      return;
    }

    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = data!.buffer.asUint8List();

    int px(int x, int y) {
      final i = (y * image.width + x) * 4;
      return (rgba[i] << 24) |
          (rgba[i + 1] << 16) |
          (rgba[i + 2] << 8) |
          rgba[i + 3];
    }

    // ignore: avoid_print
    print('SIZE ${image.width}x${image.height}');

    for (final pair in pointsSpec.split(';')) {
      final parts = pair.split(',');
      if (parts.length != 2) continue;
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);
      if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
      final argb = px(x, y);
      final hex = argb.toRadixString(16).padLeft(8, '0');
      // ignore: avoid_print
      print('PX $x,$y #$hex');
    }
    expect(image.width, greaterThan(0));
  }, skip: _pngPath.isEmpty ? 'pass --dart-define=PNG=<file>' : null);
}
