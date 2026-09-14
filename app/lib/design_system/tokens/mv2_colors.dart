import 'package:flutter/widgets.dart';

/// MV2 color tokens.
///
/// Baseline values come from `docs/04-design-system.md` (Light / Dark tables).
/// Values marked `[ext]` are additions required by the design mockups in
/// `designs/` that the doc did not name explicitly (third text tier, node
/// palette, glass fills, divider-on-surface). They must be reflected back into
/// the doc before Phase 6.
@immutable
class Mv2Colors {
  const Mv2Colors({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.elevatedSurface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.divider,
    required this.accent,
    required this.accentSoft,
    required this.accentContrast,
    required this.glassBackground,
    required this.glassBorder,
    required this.glassHighlight,
    required this.scrim,
    required this.success,
    required this.danger,
    required this.warning,
    required this.unreadDot,
    required this.shimmerBase,
    required this.shimmerHighlight,
  });

  final Brightness brightness;

  /// App background — the page canvas behind every surface.
  final Color background;

  /// Default card / list surface.
  final Color surface;

  /// Dark mode only elevated surface (nested cards, sheets). Equal to
  /// [surface] in light mode.
  final Color elevatedSurface;

  final Color textPrimary;
  final Color textSecondary;

  /// `[ext]` Metadata tier (relative timestamps, reply counts, hints).
  final Color textTertiary;

  /// Hairline border around surfaces.
  final Color border;

  /// `[ext]` In-surface separator (between list rows inside one card).
  final Color divider;

  final Color accent;

  /// `[ext]` Aliased to the doc's `Accent Soft` (accent at 8% alpha).
  final Color accentSoft;

  /// Foreground on top of [accent].
  final Color accentContrast;

  /// Floating navigation / action bar fill (parsed from `rgba(...,0.78)`).
  final Color glassBackground;

  /// 1px low-alpha border for glass surfaces.
  final Color glassBorder;

  /// `[ext]` Inner top highlight used to fake the glass rim.
  final Color glassHighlight;

  /// Modal scrim.
  final Color scrim;

  final Color success;
  final Color danger;
  final Color warning;

  /// Accent used for the unread notification dot.
  final Color unreadDot;

  /// `[ext]` Skeleton shimmer.
  final Color shimmerBase;
  final Color shimmerHighlight;

  static const light = Mv2Colors(
    brightness: Brightness.light,
    background: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    elevatedSurface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF16181D),
    textSecondary: Color(0xFF777D87),
    textTertiary: Color(0xFFA0A6B0),
    border: Color(0xFFE8EAED),
    divider: Color(0xFFF0F2F5),
    accent: Color(0xFF2563EB),
    accentSoft: Color(0x142563EB),
    accentContrast: Color(0xFFFFFFFF),
    glassBackground: Color(0xC7FFFFFF),
    glassBorder: Color(0x14000000),
    glassHighlight: Color(0xB3FFFFFF),
    scrim: Color(0x33000000),
    success: Color(0xFF16A34A),
    danger: Color(0xFFDC2626),
    warning: Color(0xFFD97706),
    unreadDot: Color(0xFF2563EB),
    shimmerBase: Color(0xFFEDEFF3),
    shimmerHighlight: Color(0xFFF7F8FA),
  );

  static const dark = Mv2Colors(
    brightness: Brightness.dark,
    background: Color(0xFF0E0F11),
    surface: Color(0xFF15171A),
    elevatedSurface: Color(0xFF1B1E22),
    textPrimary: Color(0xFFF4F5F7),
    textSecondary: Color(0xFF9CA2AC),
    textTertiary: Color(0xFF6E747E),
    border: Color(0x14FFFFFF),
    divider: Color(0x0FFFFFFF),
    accent: Color(0xFF4C83FF),
    accentSoft: Color(0x1F4C83FF),
    accentContrast: Color(0xFF0E0F11),
    glassBackground: Color(0xC71C1E22),
    glassBorder: Color(0x1FFFFFFF),
    glassHighlight: Color(0x14FFFFFF),
    scrim: Color(0x66000000),
    success: Color(0xFF22C55E),
    danger: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
    unreadDot: Color(0xFF4C83FF),
    shimmerBase: Color(0xFF1B1E22),
    shimmerHighlight: Color(0xFF22262B),
  );

  Mv2Colors copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? elevatedSurface,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? border,
    Color? divider,
    Color? accent,
    Color? accentSoft,
    Color? accentContrast,
    Color? glassBackground,
    Color? glassBorder,
    Color? glassHighlight,
    Color? scrim,
    Color? success,
    Color? danger,
    Color? warning,
    Color? unreadDot,
    Color? shimmerBase,
    Color? shimmerHighlight,
  }) {
    return Mv2Colors(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentContrast: accentContrast ?? this.accentContrast,
      glassBackground: glassBackground ?? this.glassBackground,
      glassBorder: glassBorder ?? this.glassBorder,
      glassHighlight: glassHighlight ?? this.glassHighlight,
      scrim: scrim ?? this.scrim,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      unreadDot: unreadDot ?? this.unreadDot,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
    );
  }

  static Mv2Colors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Node identity colors used by node icons / badges.
///
/// The mockups assign a stable hue per node family; icons are filled rounded
/// squares with a white glyph, badges use [Mv2Colors.accentSoft].
@immutable
class Mv2NodePalette {
  const Mv2NodePalette._();

  static const Map<String, Color> _byName = <String, Color>{
    'programmer': Color(0xFF2B2F36),
    'create': Color(0xFF2563EB),
    'ai': Color(0xFF4F46E5),
    'apple': Color(0xFF111114),
    'qna': Color(0xFF16A34A),
    'idev': Color(0xFF7C3AED),
    'share': Color(0xFF0EA5E9),
    'jobs': Color(0xFF0D9488),
    'security': Color(0xFF475569),
    'default': Color(0xFF64748B),
  };

  /// Returns the icon fill color for a node key (see `Mv2NodeIcon`).
  static Color fillFor(String key) => _byName[key] ?? _byName['default']!;
}
