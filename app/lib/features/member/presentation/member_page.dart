import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/models/models.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_refreshable.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/components/topic_item.dart';
import '../../../ui/primitives/mv2_avatar.dart';
import '../../topic/application/open_topic.dart';
import '../application/member_providers.dart';

/// Public member profile (`/member/{username}`).
///
/// The card reuses the identity language of `designs/07-profile-my.png`
/// (avatar + username + `V2EX #id`, then a stats strip). Unlike the signed-in
/// profile, the public page usually exposes no counters, so the strip is built
/// only from the counters that are non-null — it is hidden entirely rather than
/// claiming `0`.
class MemberPage extends ConsumerWidget {
  const MemberPage({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(memberProvider(username));
    ref.listen(
      memberProvider(username),
      (p, n) => mv2ToastLoadError(context, p, n),
    );

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(title: username, onBack: () => context.pop()),
      child: profile.when(
        skipLoadingOnReload: true,
        loading: () => const _MemberSkeleton(),
        // The API folds a 404 into `null`, but a direct [NotFoundFailure] can
        // still arrive from the transport — both mean "no such member".
        error: (error, _) => error is NotFoundFailure
            ? const _MemberNotFound()
            : Mv2StateView(
                kind: Mv2StateKind.error,
                actionLabel: '重试',
                onAction: () => ref.invalidate(memberProvider(username)),
              ),
        data: (data) => data == null
            ? const _MemberNotFound()
            : Mv2Refreshable(
                onRefresh: () => ref.refresh(memberProvider(username).future),
                child: _MemberBody(profile: data),
              ),
      ),
    );
  }
}

/// Empty state for a missing/renamed member.
class _MemberNotFound extends StatelessWidget {
  const _MemberNotFound();

  @override
  Widget build(BuildContext context) {
    return const Mv2StateView(
      kind: Mv2StateKind.empty,
      title: '用户不存在',
      description: '该用户可能已注销，或用户名有误。',
    );
  }
}

/// Scrollable profile: identity card, optional stats strip, recent topics.
class _MemberBody extends StatelessWidget {
  const _MemberBody({required this.profile});

  final V2Profile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final topics = profile.recentTopics;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x3,
        Mv2Spacing.pageNarrow,
        Mv2PageScaffold.bottomContentInset(context),
      ),
      children: <Widget>[
        _MemberHeaderCard(profile: profile),
        if (topics.isNotEmpty) ...<Widget>[
          const SizedBox(height: Mv2Spacing.x5),
          Text(
            '最近主题',
            style: context.text.sectionTitle.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: Mv2Spacing.x3),
          for (var i = 0; i < topics.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: Mv2Spacing.x3),
            TopicItem(
              topic: topics[i],
              onTap: () => openTopic(context, topics[i].id, source: 'member'),
            ),
          ],
        ],
      ],
    );
  }
}

/// Identity card: avatar + username + member number + tagline, and the stat
/// strip when the page exposes counters.
class _MemberHeaderCard extends StatelessWidget {
  const _MemberHeaderCard({required this.profile});

  final V2Profile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final user = profile.user;
    final tagline = user.tagline;
    final memberLabel = user.id == null ? 'V2EX' : 'V2EX #${user.id}';
    // `V2EX #1 · 加入于 2010-04-25` when the page exposes the join date.
    final subtitle = profile.joinedAtLabel == null
        ? memberLabel
        : '$memberLabel · 加入于 ${profile.joinedAtLabel}';

    // Only counters present on this page are shown; `null` is never rendered
    // as `0`.
    final stats = <(String, String)>[
      if (profile.topicCount != null) ('${profile.topicCount}', '主题'),
      if (profile.replyCount != null) ('${profile.replyCount}', '回复'),
      if (profile.favoriteCount != null) ('${profile.favoriteCount}', '收藏'),
    ];

    return Mv2Surface(
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Mv2Avatar(user: user, size: 56),
              const SizedBox(width: Mv2Spacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      user.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.itemTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: context.text.metadata.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (tagline != null && tagline.isNotEmpty) ...<Widget>[
                      const SizedBox(height: Mv2Spacing.x1),
                      Text(
                        tagline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (stats.isNotEmpty) ...<Widget>[
            const SizedBox(height: Mv2Spacing.x4),
            Row(
              children: <Widget>[
                for (var i = 0; i < stats.length; i++) ...<Widget>[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: Mv2Spacing.x8,
                      color: colors.divider,
                    ),
                  Expanded(
                    child: _StatTile(value: stats[i].$1, label: stats[i].$2),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One third of the profile statistics strip.
class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: context.text.stat.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: Mv2Spacing.x1),
        Text(
          label,
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// Profile-shaped skeleton shown while `/member/{username}` is in flight.
class _MemberSkeleton extends StatelessWidget {
  const _MemberSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x3,
        Mv2Spacing.pageNarrow,
        Mv2PageScaffold.bottomContentInset(context),
      ),
      children: const <Widget>[
        Mv2Surface(
          padding: EdgeInsets.all(Mv2Spacing.x4),
          child: Row(
            children: <Widget>[
              Mv2SkeletonBox(width: 56, height: 56, radius: Mv2Radius.pill),
              SizedBox(width: Mv2Spacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Mv2SkeletonBox(width: 120, height: 18),
                    SizedBox(height: Mv2Spacing.x2),
                    Mv2SkeletonBox(width: 72, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: Mv2Spacing.x5),
        TopicItemSkeleton(),
        SizedBox(height: Mv2Spacing.x3),
        TopicItemSkeleton(),
      ],
    );
  }
}
