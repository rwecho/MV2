import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../shared/models/models.dart';

/// Keeps full site metadata when it fits, then shortens time and removes via.
/// Widths use the same styles, direction and text scale as the rendered text.
class Mv2ReplyHeader extends StatelessWidget {
  const Mv2ReplyHeader({super.key, required this.reply, this.onAuthorTap});

  final V2Reply reply;
  final VoidCallback? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final name = '@${reply.author.username}';
    final nameStyle = context.text.bodyStrong.copyWith(
      color: context.colors.textPrimary,
    );
    final metadataStyle = context.text.metadata.copyWith(
      color: context.colors.textTertiary,
    );
    final badgeStyle = context.text.badge;
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final full = '#${reply.floor} · ${reply.createdAtLabel}';
        final compact =
            '#${reply.floor} · ${mv2CompactReplyTime(reply.createdAtLabel)}';
        final candidates = <String>[
          full,
          compact,
          compact.replaceFirst(
            RegExp(r'\s+via\s+', caseSensitive: false),
            ' · ',
          ),
        ];
        final badgeWidth = reply.badges.fold<double>(
          0,
          (width, badge) => width + 4 + 10 + measure(badge, badgeStyle),
        );
        final nameWidth = measure(name, nameStyle);
        var label = candidates.last;
        for (final candidate in candidates) {
          if (nameWidth + badgeWidth + 8 + measure(candidate, metadataStyle) <=
              constraints.maxWidth) {
            label = candidate;
            break;
          }
        }
        // Even an unusually long name retains space; secondary metadata is
        // constrained too, so it can never consume the entire header again.
        final identityWidth = math.min(
          nameWidth + badgeWidth,
          constraints.maxWidth * 0.6,
        );
        final metadataWidth = math.min(
          measure(label, metadataStyle),
          math.max(0.0, constraints.maxWidth - identityWidth - 8),
        );
        return Row(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onAuthorTap,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      ),
                    ),
                  ),
                  // Wrap badges inside a bounded area at extreme text scales.
                  if (reply.badges.isNotEmpty)
                    SizedBox(
                      width: math.min(
                        badgeWidth,
                        math.max(
                              0.0,
                              constraints.maxWidth - metadataWidth - 8,
                            ) *
                            0.4,
                      ),
                      child: Wrap(
                        children: <Widget>[
                          for (final badge in reply.badges)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 4,
                              ),
                              child: _ReplyBadge(label: badge),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: metadataWidth,
              child: Tooltip(
                message: full,
                triggerMode: TooltipTriggerMode.tap,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metadataStyle,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Only recognized Chinese relative-time labels are shortened. Unknown/date
/// labels and device names are preserved instead of guessing their meaning.
String mv2CompactReplyTime(String label) {
  return label.replaceFirstMapped(
    RegExp(r'(\d+)\s*(秒|分钟|小时|天|个月|月|年)(?:\s*\d+\s*(?:秒|分钟|小时|天|个月|月|年))*\s*前'),
    (match) => '${match[1]}${match[2]}前',
  );
}

/// `OP` / `PRO` chip straight from V2EX's own `div.badge` markup.
class _ReplyBadge extends StatelessWidget {
  const _ReplyBadge({required this.label});

  final String label;

  bool get _isOwner => label.toUpperCase() == 'OP';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _isOwner ? colors.accentSoft : colors.divider,
        borderRadius: Mv2Radius.allXs,
      ),
      child: Text(
        // V2EX's own label is `OP` and that is the established convention —
        // do not translate it to 楼主.
        label,
        style: context.text.badge.copyWith(
          color: _isOwner ? colors.accent : colors.textSecondary,
        ),
      ),
    );
  }
}
