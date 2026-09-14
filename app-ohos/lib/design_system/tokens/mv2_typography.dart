import 'package:flutter/material.dart';

/// MV2 typography tokens (`docs/04-design-system.md` §5).
///
/// System font only — no bundled font, so Chinese fallback stays stable on
/// both iOS (PingFang SC) and Android (Source Han / Noto).
///
/// Every size is expressed at the default reading scale and multiplied by
/// [scale], which is driven by the `字体大小` setting (small 0.875 / default
/// 1.0 / large 1.125 — identical to the legacy app's 14/16/18 root sizes).
@immutable
class Mv2Typography {
  const Mv2Typography._(this.scale);

  final double scale;

  const Mv2Typography.standard() : this._(1);

  factory Mv2Typography.forScale(double scale) => Mv2Typography._(scale);

  static const Mv2Typography standardInstance = Mv2Typography.standard();

  double _s(double base) => base * scale;

  // ---------------------------------------------------------------- headings

  /// Page title, e.g. `通知` / `节点` / `我的` (28/700).
  TextStyle get pageTitle => TextStyle(
    fontSize: _s(28),
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  /// Section title, e.g. `热门节点` (20/700).
  TextStyle get sectionTitle => TextStyle(
    fontSize: _s(20),
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
  );

  /// Topic title in feed cards and detail header (17/700).
  TextStyle get topicTitle => TextStyle(
    fontSize: _s(17),
    height: 1.4,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
  );

  /// Detail body heading — same weight, wider line height for long prose.
  TextStyle get topicTitleLarge => TextStyle(
    fontSize: _s(21),
    height: 1.35,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  /// Non-title row label, e.g. settings entries (16/600).
  TextStyle get itemTitle =>
      TextStyle(fontSize: _s(16), height: 1.35, fontWeight: FontWeight.w600);

  // ------------------------------------------------------------------- body

  /// Default reading body (16/400).
  TextStyle get body =>
      TextStyle(fontSize: _s(16), height: 1.6, fontWeight: FontWeight.w400);

  /// Feed excerpt / secondary paragraph (15/400).
  TextStyle get bodySmall =>
      TextStyle(fontSize: _s(15), height: 1.5, fontWeight: FontWeight.w400);

  /// Emphasised inline value (15/600).
  TextStyle get bodyStrong =>
      TextStyle(fontSize: _s(15), height: 1.5, fontWeight: FontWeight.w600);

  /// Long-form reading body for topic Markdown (16/1.75).
  ///
  /// Taller than [body] and with a hair of letter spacing: CJK glyphs are
  /// dense, so 1.6 reads cramped once a paragraph runs several lines.
  TextStyle get reading => TextStyle(
    fontSize: _s(16),
    height: 1.75,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  /// Long-form reading at reply size (15/1.7).
  TextStyle get readingSmall => TextStyle(
    fontSize: _s(15),
    height: 1.7,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  // -------------------------------------------------------------- metadata

  /// Author / time / counts (13/400).
  TextStyle get metadata =>
      TextStyle(fontSize: _s(13), height: 1.35, fontWeight: FontWeight.w400);

  /// Node badge / chip label (12/600).
  TextStyle get badge => TextStyle(
    fontSize: _s(12),
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Button / action label (15/600).
  TextStyle get button =>
      TextStyle(fontSize: _s(15), height: 1.2, fontWeight: FontWeight.w600);

  /// Bottom tab bar label (11/600).
  TextStyle get tabLabel =>
      TextStyle(fontSize: _s(11), height: 1.2, fontWeight: FontWeight.w600);

  /// Large numeric statistic in the profile header (20/700).
  TextStyle get stat =>
      TextStyle(fontSize: _s(20), height: 1.2, fontWeight: FontWeight.w700);

  Mv2Typography copyWith({double? scale}) =>
      Mv2Typography._(scale ?? this.scale);

  /// Material [TextTheme] built from these tokens, so plain Material widgets
  /// (TextField, SnackBar, ...) inherit the MV2 scale.
  TextTheme applyTo(TextTheme base, Color color, Color secondary) {
    return base.copyWith(
      displaySmall: pageTitle.copyWith(color: color),
      headlineSmall: pageTitle.copyWith(color: color),
      titleLarge: sectionTitle.copyWith(color: color),
      titleMedium: topicTitle.copyWith(color: color),
      titleSmall: itemTitle.copyWith(color: color),
      bodyLarge: body.copyWith(color: color),
      bodyMedium: bodySmall.copyWith(color: secondary),
      bodySmall: metadata.copyWith(color: secondary),
      labelLarge: button.copyWith(color: color),
      labelMedium: badge.copyWith(color: secondary),
      labelSmall: tabLabel.copyWith(color: secondary),
    );
  }
}
