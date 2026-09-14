import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_radius.dart';

/// Bridges MV2 tokens into `shadcn_ui`.
///
/// `shadcn_ui` is a **primitive** dependency only (`docs/05-shadcn-boundaries.md`):
/// it must never supply the product look. Every colour, radius and text style
/// handed to it comes from `Mv2Colors` / `Mv2Radius` / `Mv2Typography`, so the
/// Shad defaults (slate palette, 6px radius) can never leak into the UI.
abstract final class Mv2ShadTheme {
  static ShadThemeData of(BuildContext context) {
    final mv2 = context.mv2;
    final c = mv2.colors;

    return ShadThemeData(
      brightness: c.brightness,
      radius: BorderRadius.circular(Mv2Radius.mdValue),
      colorScheme: c.brightness == Brightness.dark
          ? ShadZincColorScheme.dark(
              background: c.background,
              foreground: c.textPrimary,
              card: c.elevatedSurface,
              cardForeground: c.textPrimary,
              popover: c.elevatedSurface,
              popoverForeground: c.textPrimary,
              primary: c.accent,
              primaryForeground: c.accentContrast,
              secondary: c.surface,
              secondaryForeground: c.textPrimary,
              muted: c.divider,
              mutedForeground: c.textSecondary,
              accent: c.accentSoft,
              accentForeground: c.accent,
              destructive: c.danger,
              destructiveForeground: c.accentContrast,
              border: c.border,
              input: c.border,
              ring: c.accent,
              selection: c.accentSoft,
            )
          : ShadZincColorScheme.light(
              background: c.background,
              foreground: c.textPrimary,
              card: c.surface,
              cardForeground: c.textPrimary,
              popover: c.surface,
              popoverForeground: c.textPrimary,
              primary: c.accent,
              primaryForeground: c.accentContrast,
              secondary: c.surface,
              secondaryForeground: c.textPrimary,
              muted: c.divider,
              mutedForeground: c.textSecondary,
              accent: c.accentSoft,
              accentForeground: c.accent,
              destructive: c.danger,
              destructiveForeground: c.accentContrast,
              border: c.border,
              input: c.border,
              ring: c.accent,
              selection: c.accentSoft,
            ),
      textTheme: ShadTextTheme(
        h1Large: mv2.typography.pageTitle,
        h1: mv2.typography.pageTitle,
        h2: mv2.typography.sectionTitle,
        h3: mv2.typography.topicTitle,
        h4: mv2.typography.itemTitle,
        p: mv2.typography.body,
        lead: mv2.typography.bodySmall,
        large: mv2.typography.itemTitle,
        small: mv2.typography.metadata,
        muted: mv2.typography.metadata.copyWith(color: c.textTertiary),
      ),
    );
  }
}

/// Root widget that injects the Shad primitive theme under the MV2 theme.
class Mv2ShadScope extends StatelessWidget {
  const Mv2ShadScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShadTheme(data: Mv2ShadTheme.of(context), child: child);
  }
}
