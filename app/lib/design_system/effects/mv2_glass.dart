import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/mv2_theme.dart';
import '../tokens/mv2_radius.dart';

/// MV2 elevation recipes.
///
/// The design language is "light floating", not Material elevation: one very
/// soft ambient shadow, never stacked shadows.
abstract final class Mv2Shadows {
  /// Default card shadow (light mode only; dark mode relies on surface color).
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 16, offset: Offset(0, 4)),
  ];

  /// Floating navigation / action bar.
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(color: Color(0x140F172A), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x080F172A), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static List<BoxShadow> forBrightness(
    Brightness brightness,
    List<BoxShadow> light,
  ) => brightness == Brightness.dark ? const <BoxShadow>[] : light;
}

/// A frosted surface used **only** for navigation and action layers
/// (`docs/04` §1: "Glass 只属于 Navigation / Actions").
///
/// Degrades to a solid fill when [Mv2Theme.reduceTransparency] is set, when
/// blurring is unsupported, or when the platform reports reduced transparency.
class Mv2GlassSurface extends StatelessWidget {
  const Mv2GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = Mv2Radius.nav,
    this.blur = 20,
    this.padding,
    this.shadows,
    this.bordered = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadows;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final mv2 = context.mv2;
    final colors = mv2.colors;

    final reduceTransparency =
        mv2.reduceTransparency ||
        MediaQuery.maybeDisableAnimationsOf(context) == true;

    final decoration = BoxDecoration(
      color: reduceTransparency
          ? (mv2.isDark ? colors.elevatedSurface : colors.surface)
          : colors.glassBackground,
      borderRadius: borderRadius,
      border: bordered ? Border.all(color: colors.glassBorder) : null,
      boxShadow:
          shadows ??
          Mv2Shadows.forBrightness(colors.brightness, Mv2Shadows.floating),
    );

    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    if (reduceTransparency) {
      return DecoratedBox(decoration: decoration, child: content);
    }

    return DecoratedBox(
      decoration: decoration,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        ),
      ),
    );
  }
}

/// A plain MV2 card: hairline border, generous radius, optional soft shadow.
/// Used for content surfaces (settings groups, topic body, node cards) —
/// deliberately **not** used for feed items (`docs/07`).
class Mv2Surface extends StatelessWidget {
  const Mv2Surface({
    super.key,
    required this.child,
    this.borderRadius = Mv2Radius.allLg,
    this.padding,
    this.color,
    this.bordered = true,
    this.shadowed = true,
    this.onTap,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final bool bordered;
  final bool shadowed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final decoration = BoxDecoration(
      color: color ?? colors.surface,
      borderRadius: borderRadius,
      border: bordered ? Border.all(color: colors.border) : null,
      boxShadow: shadowed
          ? Mv2Shadows.forBrightness(colors.brightness, Mv2Shadows.card)
          : null,
    );

    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }

    return DecoratedBox(
      decoration: decoration,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          highlightColor: colors.accentSoft,
          splashColor: Colors.transparent,
          child: content,
        ),
      ),
    );
  }
}
