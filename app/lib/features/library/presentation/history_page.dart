import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/models/models.dart';
import '../../../ui/components/mv2_error_feedback.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_refreshable.dart';
import '../../../ui/components/states/mv2_skeleton.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/components/topic_item.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../application/library_providers.dart';
import 'confirm_dialog.dart';

/// 浏览历史 — a secondary list page over the local history table.
///
/// Reads newest-viewed first and offers the same clear / long-press-remove
/// affordances as 稍后阅读 so both pages behave identically.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final bottomInset = Mv2PageScaffold.bottomContentInset(context);
    Future<void> refresh() => ref.refresh(historyProvider.future);
    ref.listen(historyProvider, (p, n) => mv2ToastLoadError(context, p, n));

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(
        title: '浏览历史',
        onBack: () => context.pop(),
        actions: <Widget>[
          Mv2IconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: '清空',
            onPressed: (history.value?.isEmpty ?? true)
                ? null
                : () => _clear(context, ref),
          ),
        ],
      ),
      child: history.when(
        skipLoadingOnReload: true,
        loading: () => Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: const TopicListSkeleton(),
        ),
        error: (_, _) => Mv2RefreshableFill(
          onRefresh: refresh,
          child: Mv2StateView(
            kind: Mv2StateKind.error,
            actionLabel: '重试',
            onAction: () => ref.invalidate(historyProvider),
          ),
        ),
        data: (List<V2Topic> topics) {
          if (topics.isEmpty) {
            return Mv2RefreshableFill(
              onRefresh: refresh,
              child: const Mv2StateView(
                kind: Mv2StateKind.empty,
                title: '还没有浏览记录',
                description: '看过的主题会按时间顺序出现在这里。',
              ),
            );
          }
          return Mv2Refreshable(
            onRefresh: refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                Mv2Spacing.pageNarrow,
                0,
                Mv2Spacing.pageNarrow,
                bottomInset,
              ),
              itemCount: topics.length,
              separatorBuilder: (_, _) => const SizedBox(height: Mv2Spacing.x3),
              itemBuilder: (context, index) {
                final topic = topics[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _removeOne(context, ref, topic),
                  child: TopicItem(
                    topic: topic,
                    onTap: () => context.push('/topic/${topic.id}'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '清空浏览历史',
      message: '将清空全部浏览历史，确定继续吗？',
      confirmLabel: '清空',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(libraryControllerProvider).clearHistory();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('浏览历史已清空')));
    } catch (error) {
      if (!context.mounted) return;
      mv2ShowError(context, error);
    }
  }

  Future<void> _removeOne(
    BuildContext context,
    WidgetRef ref,
    V2Topic topic,
  ) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除记录',
      message: '将从浏览历史中删除「${topic.title}」？',
      confirmLabel: '删除',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(libraryControllerProvider).removeHistory(topic.id);
    } catch (error) {
      if (!context.mounted) return;
      mv2ShowError(context, error);
    }
  }
}
