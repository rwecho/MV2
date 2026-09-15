import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/models/models.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_refreshable.dart';
import '../../../ui/components/mv2_segmented_tabs.dart';
import '../../../ui/components/notification_item.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../auth/presentation/mv2_account_avatar.dart';
import '../../topic/application/open_topic.dart';
import '../application/notifications_providers.dart';

/// Grouped notification feed for `designs/06-notifications.png`.
///
/// Reads `/notifications` through [notificationsControllerProvider] and pages
/// with infinite scroll. Anonymous sessions get `302 → /signin`, which the API
/// maps to a signed-out page rendered as the login call to action.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsControllerProvider);

    // The controller folds failures into state, so surface them as a toast for
    // both the first load and a pull-to-refresh.
    ref.listen(notificationsControllerProvider.select((s) => s.failure), (
      previous,
      next,
    ) {
      if (next != null && next != previous) mv2ShowError(context, next);
    });

    return Mv2PageScaffold(
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Mv2PageHeader(
            title: '通知',
            subtitle: '与优秀的开发者社区',
            actions: <Widget>[
              const Mv2IconButton(icon: Icons.search_rounded, filled: true),
              const SizedBox(width: Mv2Spacing.x2),
              const Mv2AccountAvatar(),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Mv2Spacing.x2),
            child: Mv2SegmentedTabs(
              items: const <String>['全部', '回复', '@我'],
              selectedIndex: _tabIndex,
              onChanged: (index) => setState(() => _tabIndex = index),
              padded: true,
            ),
          ),
        ],
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Load the next page once the list is within ~400px of the bottom;
          // the controller de-duplicates concurrent/duplicate calls.
          if (notification.metrics.extentAfter < 400) {
            ref.read(notificationsControllerProvider.notifier).loadMore();
          }
          return false;
        },
        child: Mv2Refreshable(
          onRefresh: () =>
              ref.read(notificationsControllerProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              Mv2Spacing.pageNarrow,
              Mv2Spacing.x4,
              Mv2Spacing.pageNarrow,
              Mv2PageScaffold.bottomContentInset(context),
            ),
            children: <Widget>[_body(state)],
          ),
        ),
      ),
    );
  }

  Widget _body(NotificationsState state) {
    if (state.isLoading) return const _NotificationsLoadingList();

    if (state.isSignedOut) {
      return Mv2StateView(
        kind: Mv2StateKind.empty,
        title: '登录后查看通知',
        description: '登录 V2EX 账号后，回复、@ 提及与点赞都会出现在这里。',
        actionLabel: '去登录',
        onAction: () => context.push('/login'),
      );
    }

    if (state.failed) {
      return Mv2StateView(
        kind: Mv2StateKind.error,
        actionLabel: '重试',
        onAction: () =>
            ref.read(notificationsControllerProvider.notifier).refresh(),
      );
    }

    if (state.isEmpty) {
      return const Mv2StateView(kind: Mv2StateKind.empty, title: '暂无通知');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _NotificationGroups(groups: state.groups),
        if (state.isLoadingMore) ...<Widget>[
          const SizedBox(height: Mv2Spacing.x4),
          const Center(child: Mv2SkeletonBox(width: 120, height: 12)),
        ],
      ],
    );
  }
}

/// Inline section titles plus their notification rows.
class _NotificationGroups extends StatelessWidget {
  const _NotificationGroups({required this.groups});

  final List<V2NotificationGroup> groups;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final children = <Widget>[];

    for (var i = 0; i < groups.length; i++) {
      if (i > 0) children.add(const SizedBox(height: Mv2Spacing.x5));
      children.add(
        Text(
          groups[i].title,
          style: context.text.itemTitle.copyWith(color: colors.textPrimary),
        ),
      );
      children.add(const SizedBox(height: Mv2Spacing.x3));

      final items = groups[i].items;
      for (var j = 0; j < items.length; j++) {
        if (j > 0) children.add(const SizedBox(height: Mv2Spacing.x3));
        final item = items[j];
        final topicId = item.topicId;
        children.add(
          NotificationItem(
            notification: item,
            // The `a.topic-link` href supplies the destination topic.
            onTap: topicId == null
                ? null
                : () => openTopic(context, topicId),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Loading placeholder matching [NotificationItem] metrics.
class _NotificationsLoadingList extends StatelessWidget {
  const _NotificationsLoadingList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        _NotificationSkeleton(),
        SizedBox(height: Mv2Spacing.x3),
        _NotificationSkeleton(),
        SizedBox(height: Mv2Spacing.x3),
        _NotificationSkeleton(),
        SizedBox(height: Mv2Spacing.x3),
        _NotificationSkeleton(),
        SizedBox(height: Mv2Spacing.x3),
        _NotificationSkeleton(),
      ],
    );
  }
}

class _NotificationSkeleton extends StatelessWidget {
  const _NotificationSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(Mv2Spacing.x4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Mv2Radius.allMd,
        border: Border.all(color: colors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Mv2SkeletonBox(width: 38, height: 38, radius: Mv2Radius.pill),
          SizedBox(width: Mv2Spacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Mv2SkeletonBox(width: 140, height: 14),
                    Spacer(),
                    Mv2SkeletonBox(width: 48, height: 12),
                  ],
                ),
                SizedBox(height: Mv2Spacing.x3),
                Mv2SkeletonBox(width: double.infinity, height: 12),
                SizedBox(height: Mv2Spacing.x1),
                Mv2SkeletonBox(width: 220, height: 12),
                SizedBox(height: Mv2Spacing.x3),
                Mv2SkeletonBox(width: 160, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
