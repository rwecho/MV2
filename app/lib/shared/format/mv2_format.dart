/// Display formatting helpers.
///
/// Kept out of widgets so the presentation layer never owns locale rules.
abstract final class Mv2Format {
  /// `12400` → `12.4k`, `980` → `980`, `1200000` → `1.2m`.
  static String compactCount(int value) {
    if (value < 1000) return '$value';
    if (value < 10000) {
      final k = value / 1000;
      return '${_trim(k)}k';
    }
    if (value < 1000000) {
      final k = value / 1000;
      return '${_trim(k)}k';
    }
    final m = value / 1000000;
    return '${_trim(m)}m';
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}
