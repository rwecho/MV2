/// MV2 spacing tokens — 4pt grid (`docs/04-design-system.md` §4).
abstract final class Mv2Spacing {
  static const double x0 = 0;
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;

  /// Narrowest supported phone width: horizontal page padding.
  static const double pageNarrow = 16;

  /// Standard / wide: horizontal page padding.
  static const double page = 20;

  /// Breakpoint above which [page] is used instead of [pageNarrow].
  static const double wideBreakpoint = 420;

  /// Content column cap on tablets (`docs/04` §6).
  static const double maxContentWidth = 600;

  /// Minimum interactive target (`docs/04` §9).
  static const double minTapTarget = 48;

  /// Resolves the horizontal page padding for a viewport [width].
  static double pageHorizontal(double width) =>
      width >= wideBreakpoint ? page : pageNarrow;
}
