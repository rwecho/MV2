import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../shared/models/models.dart';

/// Circular avatar with an offline-safe fallback.
///
/// The mockups use photographic avatars; when the network image is
/// unavailable (offline / first paint) we render a deterministic gradient tile
/// with the user's initial so layout never shifts.
class Mv2Avatar extends StatelessWidget {
  const Mv2Avatar({
    super.key,
    required this.user,
    this.size = 32,
    this.showBorder = false,
  });

  final V2User user;
  final double size;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final url = user.avatarUrl;

    final Widget image = url == null || url.isEmpty
        ? _fallback(context)
        : CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (_, _) => _fallback(context),
            errorWidget: (_, _, _) => _fallback(context),
          );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: showBorder ? Border.all(color: colors.border) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }

  Widget _fallback(BuildContext context) {
    final seed = user.username.codeUnits.fold<int>(0, (a, b) => a + b);
    final hue = (seed * 37) % 360;
    final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.32, 0.62).toColor();
    final darker = HSLColor.fromAHSL(1, hue.toDouble(), 0.34, 0.48).toColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[base, darker],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          user.username.isEmpty
              ? '?'
              : user.username.characters.first.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
