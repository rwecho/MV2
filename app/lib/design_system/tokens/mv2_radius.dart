import 'package:flutter/widgets.dart';

/// MV2 radius tokens (`docs/04-design-system.md` §3).
abstract final class Mv2Radius {
  static const double xsValue = 8;
  static const double smValue = 12;
  static const double mdValue = 16;
  static const double lgValue = 20;
  static const double xlValue = 24;

  /// Floating navigation / action bars.
  static const double navMinValue = 24;
  static const double navMaxValue = 26;

  static const Radius xs = Radius.circular(xsValue);
  static const Radius sm = Radius.circular(smValue);
  static const Radius md = Radius.circular(mdValue);
  static const Radius lg = Radius.circular(lgValue);
  static const Radius xl = Radius.circular(xlValue);

  static const BorderRadius allXs = BorderRadius.all(xs);
  static const BorderRadius allSm = BorderRadius.all(sm);
  static const BorderRadius allMd = BorderRadius.all(md);
  static const BorderRadius allLg = BorderRadius.all(lg);
  static const BorderRadius allXl = BorderRadius.all(xl);

  /// Floating tab bar / floating reply bar.
  static const BorderRadius nav = BorderRadius.all(Radius.circular(24));

  /// Pill used by segmented controls and chips.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}
