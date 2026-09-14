import 'package:flutter/material.dart';

import '../tokens/mv2_colors.dart';
import '../tokens/mv2_typography.dart';

/// MV2 design tokens exposed through the widget tree.
///
/// Widgets must read colors/typography from here (`context.mv2`) instead of
/// hard-coding values, per `docs/04-design-system.md` and `agent/AGENTS.md`.
@immutable
class Mv2Theme extends ThemeExtension<Mv2Theme> {
  const Mv2Theme({
    required this.colors,
    required this.typography,
    this.reduceTransparency = false,
  });

  final Mv2Colors colors;
  final Mv2Typography typography;

  /// Accessibility / low-end fallback (`docs/04` §9): when true, glass
  /// surfaces must render as solid fills instead of blurred translucency.
  final bool reduceTransparency;

  bool get isDark => colors.brightness == Brightness.dark;

  static Mv2Theme of(BuildContext context) {
    final theme = Theme.of(context).extension<Mv2Theme>();
    assert(theme != null, 'Mv2Theme extension is missing from ThemeData.');
    return theme!;
  }

  @override
  Mv2Theme copyWith({
    Mv2Colors? colors,
    Mv2Typography? typography,
    bool? reduceTransparency,
  }) {
    return Mv2Theme(
      colors: colors ?? this.colors,
      typography: typography ?? this.typography,
      reduceTransparency: reduceTransparency ?? this.reduceTransparency,
    );
  }

  @override
  Mv2Theme lerp(Mv2Theme? other, double t) {
    if (other == null) return this;
    // Colors and typography swap discretely with the theme, so a straight
    // endpoint pick avoids muddy mid-transition text rendering.
    return t < 0.5 ? this : other;
  }
}

/// Ergonomic accessors: `context.mv2`, `context.colors`, `context.text`.
extension Mv2ThemeContext on BuildContext {
  Mv2Theme get mv2 => Mv2Theme.of(this);

  Mv2Colors get colors => Mv2Theme.of(this).colors;

  Mv2Typography get text => Mv2Theme.of(this).typography;

  bool get isDarkMode => Mv2Theme.of(this).isDark;
}

/// Builds the Material [ThemeData] that carries the MV2 tokens.
abstract final class Mv2ThemeData {
  static ThemeData light({double textScale = 1}) =>
      _build(Mv2Colors.light, textScale);

  static ThemeData dark({double textScale = 1}) =>
      _build(Mv2Colors.dark, textScale);

  static ThemeData _build(Mv2Colors colors, double textScale) {
    final typography = Mv2Typography.forScale(textScale);
    final isDark = colors.brightness == Brightness.dark;

    final base = isDark ? ThemeData.dark() : ThemeData.light();

    final colorScheme =
        (isDark ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
              brightness: colors.brightness,
              primary: colors.accent,
              onPrimary: colors.accentContrast,
              secondary: colors.accent,
              onSecondary: colors.accentContrast,
              error: colors.danger,
              onError: colors.accentContrast,
              surface: colors.surface,
              onSurface: colors.textPrimary,
              surfaceContainerHighest: colors.elevatedSurface,
              outline: colors.border,
            );

    final textTheme = typography.applyTo(
      base.textTheme,
      colors.textPrimary,
      colors.textSecondary,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      dividerColor: colors.divider,
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: typography.sectionTitle.copyWith(
          color: colors.textPrimary,
        ),
      ),
      iconTheme: IconThemeData(color: colors.textSecondary, size: 22),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.elevatedSurface,
        contentTextStyle: typography.bodySmall.copyWith(
          color: colors.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        hintStyle: typography.bodySmall.copyWith(color: colors.textTertiary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : colors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : colors.divider,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : colors.border,
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        Mv2Theme(colors: colors, typography: typography),
      ],
    );
  }
}
