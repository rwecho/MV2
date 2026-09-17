import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/effects/mv2_glass.dart';
import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_radius.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../../shared/models/models.dart';
import '../primitives/mv2_avatar.dart';

/// Whether the notification's actor has a member page to open.
///
/// Shared by the avatar and the actor name so the two tap targets can never
/// disagree about who is reachable (V2EX has no page for 匿名).
bool _canOpenActor(V2Notification n) {
  final username = n.actor.username;
  return username.isNotEmpty && username != '匿名';
}

/// Notification row for `designs/06-notifications.png`.
class NotificationItem extends StatelessWidget {
  const NotificationItem({super.key, required this.notification, this.onTap});

  final V2Notification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final n = notification;

    return Mv2Surface(
      borderRadius: Mv2Radius.allMd,
      shadowed: false,
      onTap: onTap,
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Unread marker column — keeps text left-aligned whether or not the
          // row is unread, so the list does not jitter after marking read.
          SizedBox(
            width: 14,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: n.isUnread
                  ? Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: colors.unreadDot,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: Mv2Spacing.x2),
          // The avatar is its own tap target, matching the actor name next to
          // it: tapping the person goes to their page, not to the topic the
          // card points at.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _canOpenActor(n)
                ? () => context.push('/member/${n.actor.username}')
                : null,
            child: Mv2Avatar(user: n.actor, size: 38),
          ),
          const SizedBox(width: Mv2Spacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: _ActionLine(notification: n)),
                    const SizedBox(width: Mv2Spacing.x2),
                    Text(
                      n.timeLabel,
                      style: context.text.metadata.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Mv2Spacing.x2),
                Text(
                  '“${n.quote}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: Mv2Spacing.x2),
                Text(
                  n.sourceTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.metadata.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionLine extends StatefulWidget {
  const _ActionLine({required this.notification});

  final V2Notification notification;

  @override
  State<_ActionLine> createState() => _ActionLineState();
}

class _ActionLineState extends State<_ActionLine> {
  /// The actor name is a tappable [TextSpan], so its recognizer is owned here
  /// and disposed with the row instead of being rebuilt on every frame.
  TapGestureRecognizer? _actorRecognizer;

  bool get _canOpen => _canOpenActor(widget.notification);

  @override
  void initState() {
    super.initState();
    _syncRecognizer();
  }

  @override
  void didUpdateWidget(covariant _ActionLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notification.actor.username !=
        widget.notification.actor.username) {
      _syncRecognizer();
    }
  }

  void _syncRecognizer() {
    _actorRecognizer?.dispose();
    _actorRecognizer = null;
    if (!_canOpen) return;
    _actorRecognizer = TapGestureRecognizer()
      ..onTap = () =>
          context.push('/member/${widget.notification.actor.username}');
  }

  @override
  void dispose() {
    _actorRecognizer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final actor = widget.notification.actor.username;
    final action = switch (widget.notification.kind) {
      NotificationKind.reply => ' 回复了你的主题',
      NotificationKind.mention => ' 在评论中 @了你',
      NotificationKind.like => ' 赞了你的回复',
      NotificationKind.favorite => ' 收藏了你的主题',
    };

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: actor,
            recognizer: _actorRecognizer,
            style: context.text.bodyStrong.copyWith(color: colors.textPrimary),
          ),
          TextSpan(
            text: action,
            style: context.text.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
