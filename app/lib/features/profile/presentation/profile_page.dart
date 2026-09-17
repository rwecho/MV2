import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/models/daily_mission.dart';
import '../../../shared/models/models.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_settings_row.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/primitives/mv2_avatar.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/daily_mission_providers.dart';
import '../application/profile_providers.dart';

/// `我的` tab — `designs/07-profile-my.png`.
///
/// The floating tab bar belongs to the shell, so this page never passes
/// `currentTab`; it only reserves bottom clearance for the bar.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final profile = ref.watch(profileProvider);

    return Mv2PageScaffold(
      header: Mv2PageHeader(
        title: '我的',
        subtitle: 'Wake Up to V2EX',
        actions: <Widget>[
          Mv2IconButton(
            icon: Icons.settings_outlined,
            filled: true,
            tooltip: '设置',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Mv2Spacing.pageNarrow,
          0,
          Mv2Spacing.pageNarrow,
          Mv2PageScaffold.bottomContentInset(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!signedIn)
              const _LoginCard()
            else
              profile.when(
                loading: () => const _ProfileCardSkeleton(),
                error: (_, _) => Mv2StateView(
                  kind: Mv2StateKind.error,
                  compact: true,
                  actionLabel: '重试',
                  onAction: () => ref.invalidate(profileProvider),
                ),
                data: (data) => data == null
                    ? const _LoginCard()
                    : _ProfileCard(profile: data),
              ),

            // ------------------------------------------------------- content
            Mv2SettingsGroup(
              badge: '内容',
              children: <Widget>[
                Mv2SettingsRow(
                  label: '我的主题',
                  icon: Icons.article_outlined,
                  onTap: () => context.push('/my/topics'),
                ),
                Mv2SettingsRow(
                  label: '我的回复',
                  icon: Icons.chat_bubble_outline_rounded,
                  onTap: () => context.push('/my/replies'),
                ),
                Mv2SettingsRow(
                  label: '收藏',
                  icon: Icons.star_border_rounded,
                  onTap: () => context.push('/my/favorites'),
                ),
                Mv2SettingsRow(
                  label: '稍后阅读',
                  icon: Icons.schedule_rounded,
                  onTap: () => context.push('/read-later'),
                ),
                Mv2SettingsRow(
                  label: '浏览历史',
                  icon: Icons.history_rounded,
                  onTap: () => context.push('/history'),
                  showDivider: false,
                ),
              ],
            ),

            // ------------------------------------------------------ community
            Mv2SettingsGroup(
              badge: '社区',
              children: <Widget>[
                // Design addition (no mockup): only meaningful while signed in.
                if (signedIn) const _DailyCheckInRow(),
                Mv2SettingsRow(
                  label: '屏蔽用户',
                  icon: Icons.person_off_outlined,
                  onTap: () => context.push('/blocked-users'),
                ),
                Mv2SettingsRow(
                  label: '我的节点',
                  icon: Icons.tag_rounded,
                  onTap: () => context.push('/my/nodes'),
                  showDivider: false,
                ),
              ],
            ),

            // ------------------------------------------------------------ app
            Mv2SettingsGroup(
              badge: 'App',
              children: <Widget>[
                Mv2SettingsRow(
                  label: '外观',
                  icon: Icons.palette_outlined,
                  onTap: () => context.push('/settings'),
                ),
                Mv2SettingsRow(
                  label: '阅读设置',
                  icon: Icons.text_fields_rounded,
                  onTap: () => context.push('/settings'),
                ),
                Mv2SettingsRow(
                  label: '通知',
                  icon: Icons.notifications_none_rounded,
                  onTap: () => context.push('/notifications'),
                ),
                Mv2SettingsRow(
                  label: '数据与隐私',
                  icon: Icons.verified_user_outlined,
                  onTap: () => context.push('/settings'),
                ),
                Mv2SettingsRow(
                  label: '关于 MV2',
                  icon: Icons.info_outline_rounded,
                  onTap: () => context.push('/about'),
                  showDivider: signedIn,
                ),
                // Design addition (no mockup): destructive, signed in only.
                if (signedIn)
                  _LogoutRow(onTap: () => _confirmSignOut(context, ref)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Confirms, then forgets the session (cookie jar + persisted account).
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新登录才能同步主题、回复与收藏。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
  }
}

/// 每日签到 row (community group, signed in only).
///
/// Design addition: there is no mockup for it, so it reuses [Mv2SettingsRow]
/// with the same tokens/metrics as its siblings.
class _DailyCheckInRow extends ConsumerWidget {
  const _DailyCheckInRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mission = ref.watch(dailyMissionProvider);
    final value = mission.when(
      data: (data) =>
          data.alreadyCheckedIn ? '已领取' : (data.continuousDaysLabel ?? '签到'),
      loading: () => null,
      error: (_, _) => null,
    );

    return Mv2SettingsRow(
      label: '每日签到',
      icon: Icons.event_available_outlined,
      value: value,
      onTap: () => _checkIn(context, ref, mission.value),
    );
  }

  Future<void> _checkIn(
    BuildContext context,
    WidgetRef ref,
    V2DailyMission? mission,
  ) async {
    if (mission?.alreadyCheckedIn ?? false) {
      Mv2Analytics.logDailyCheckin(result: 'already');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('今日已领取')));
      return;
    }
    try {
      await ref.read(checkInProvider.notifier).checkIn();
      Mv2Analytics.logDailyCheckin(result: 'success');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('签到成功')));
    } catch (_) {
      Mv2Analytics.logDailyCheckin(result: 'failed');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('签到失败，请稍后重试')));
    }
  }
}

/// 退出登录 row (App group, signed in only).
///
/// Design addition: [Mv2SettingsRow] has no label-colour hook, so this mirrors
/// its exact metrics/tokens while tinting the label and icon with
/// `colors.danger` to read as destructive.
class _LogoutRow extends StatelessWidget {
  const _LogoutRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Mv2Spacing.x4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: <Widget>[
              Icon(Icons.logout_rounded, size: 20, color: colors.danger),
              const SizedBox(width: Mv2Spacing.x3),
              Expanded(
                child: Text(
                  '退出登录',
                  style: context.text.itemTitle.copyWith(color: colors.danger),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed-in identity card: avatar + username + member number + stats.
///
/// The chevron makes it a tap target: it opens the member's own public page,
/// the same surface every other author reference in the app leads to.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final V2Profile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final user = profile.user;
    final memberLabel = user.id == null ? 'V2EX' : 'V2EX #${user.id}';
    final username = user.username;
    final canOpen = username.isNotEmpty && username != '匿名';

    return Mv2Surface(
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      onTap: canOpen ? () => context.push('/member/$username') : null,
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
                      style: context.text.itemTitle.copyWith(
                        fontSize: 18,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      memberLabel,
                      style: context.text.metadata.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.textTertiary,
              ),
            ],
          ),
          // V2EX only exposes these counters on signed-in surfaces, and the
          // public member page has none — hide the strip instead of claiming 0.
          if (profile.topicCount != null ||
              profile.replyCount != null ||
              profile.favoriteCount != null) ...<Widget>[
            const SizedBox(height: Mv2Spacing.x4),
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatTile(
                    value: _statValue(profile.topicCount),
                    label: '主题',
                  ),
                ),
                Container(
                  width: 1,
                  height: Mv2Spacing.x8,
                  color: colors.divider,
                ),
                Expanded(
                  child: _StatTile(
                    value: _statValue(profile.replyCount),
                    label: '回复',
                  ),
                ),
                Container(
                  width: 1,
                  height: Mv2Spacing.x8,
                  color: colors.divider,
                ),
                Expanded(
                  child: _StatTile(
                    value: _statValue(profile.favoriteCount),
                    label: '收藏',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _statValue(int? value) => value?.toString() ?? '—';

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

/// Placeholder for [_ProfileCard] while `/member/{username}` loads.
class _ProfileCardSkeleton extends StatelessWidget {
  const _ProfileCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Mv2Surface(
      padding: EdgeInsets.all(Mv2Spacing.x4),
      child: Column(
        children: <Widget>[
          Row(
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
          SizedBox(height: Mv2Spacing.x4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Mv2SkeletonBox(width: 48, height: 24),
              Mv2SkeletonBox(width: 48, height: 24),
              Mv2SkeletonBox(width: 48, height: 24),
            ],
          ),
        ],
      ),
    );
  }
}

/// Signed-out call-to-action shown instead of [_ProfileCard].
class _LoginCard extends StatelessWidget {
  const _LoginCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Mv2Surface(
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.divider,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_outline_rounded,
              size: 26,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(width: Mv2Spacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '未登录',
                  style: context.text.itemTitle.copyWith(
                    fontSize: 18,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '登录后可同步主题、回复与收藏',
                  style: context.text.metadata.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Mv2TextButton(label: '登录', onPressed: () => context.push('/login')),
        ],
      ),
    );
  }
}
