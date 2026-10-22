import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_refreshable.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../application/honors_controller.dart';
import '../application/pro_controller.dart';
import '../data/honors_api.dart';

/// 赞助榜：所有买断永久版的支持者永久铭刻于此。
///
/// 名单来自 Worker（`/honors`），登记时由服务端用 RevenueCat 核验购买；
/// 一经铭刻不随退款移除 —— "永久"是产品承诺。
class HonorWallPage extends ConsumerStatefulWidget {
  const HonorWallPage({super.key, this.source = 'settings'});

  /// 归因参数（`honor_wall_open.source`）。
  final String source;

  @override
  ConsumerState<HonorWallPage> createState() => _HonorWallPageState();
}

class _HonorWallPageState extends ConsumerState<HonorWallPage> {
  @override
  void initState() {
    super.initState();
    Mv2Analytics.logHonorWallOpen(source: widget.source);
  }

  @override
  Widget build(BuildContext context) {
    final honors = ref.watch(honorsControllerProvider);
    final isPro = ref.watch(isProProvider);

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(title: '赞助榜', onBack: () => context.pop()),
      child: honors.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Column(
          children: [
            Expanded(
              child: Mv2StateView(
                kind: Mv2StateKind.error,
                description: '赞助榜加载失败',
                actionLabel: '重试',
                onAction: () => ref.invalidate(honorsControllerProvider),
              ),
            ),
            Mv2TextButton(
              label: '赞助 MV2 / 恢复购买',
              onPressed: () => context.push('/pro?source=feature_gate'),
            ),
            const SizedBox(height: Mv2Spacing.x6),
          ],
        ),
        data: (state) => Mv2Refreshable(
          onRefresh: () async => ref.invalidate(honorsControllerProvider),
          child: _Wall(state: state, isPro: isPro),
        ),
      ),
    );
  }
}

class _Wall extends StatelessWidget {
  const _Wall({required this.state, required this.isPro});

  final HonorsState state;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = state.entries;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x4,
        Mv2Spacing.pageNarrow,
        Mv2PageScaffold.bottomContentInset(context) + Mv2Spacing.x6,
      ),
      children: <Widget>[
        if (entries.isEmpty) ...<Widget>[
          const Mv2StateView(
            kind: Mv2StateKind.empty,
            title: '赞助榜还空着',
            description: '购买永久版后，可自愿留下公开展示的名字。',
          ),
        ] else ...<Widget>[
          for (var i = 0; i < entries.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, color: colors.divider),
            _EntryRow(index: i + 1, entry: entries[i]),
          ],
        ],
        const SizedBox(height: Mv2Spacing.x6),
        if (isPro)
          _ProFooter(state: state)
        else ...<Widget>[
          Text(
            '购买永久版后，可以自愿登记展示名；不登记也不影响 Pro 权益。',
            textAlign: TextAlign.center,
            style: context.text.bodySmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Mv2Spacing.x3),
          Mv2TextButton(
            label: '去解锁永久版',
            onPressed: () => context.push('/pro?source=feature_gate'),
          ),
        ],
      ],
    );
  }
}

/// 一条铭刻：名次 + 名字 + 铭刻日期。前三名带奖牌色。
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.index, required this.entry});

  final int index;
  final HonorEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rankColor = switch (index) {
      1 => const Color(0xFFD4A017),
      2 => const Color(0xFF9EA7B3),
      3 => const Color(0xFFB0713A),
      _ => colors.textTertiary,
    };
    final date = entry.joinedAt;
    final dateLabel =
        '${date.year}.${date.month.toString().padLeft(2, '0')}.'
        '${date.day.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Mv2Spacing.x2,
        vertical: Mv2Spacing.x3,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 32,
            child: Text(
              '$index',
              textAlign: TextAlign.center,
              style: context.text.itemTitle.copyWith(color: rankColor),
            ),
          ),
          const SizedBox(width: Mv2Spacing.x3),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.itemTitle.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: Mv2Spacing.x2),
          Text(
            dateLabel,
            style: context.text.metadata.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 已解锁用户的名片区：未铭刻 → 引导登记；已铭刻 → 安静的确认。
class _ProFooter extends ConsumerWidget {
  const _ProFooter({required this.state});
  final HonorsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        if (state.statusError != null) ...[
          Text(state.statusError!),
          Mv2TextButton(
            label: '恢复购买',
            onPressed: () => context.push('/pro?source=feature_gate'),
          ),
          Mv2TextButton(
            label: '重试',
            onPressed: () => ref.invalidate(honorsControllerProvider),
          ),
        ] else ...[
          if (state.mine != null)
            Text(state.mine!.hidden ? '你的署名已隐藏' : '你的署名：${state.mine!.name}'),
          Mv2TextButton(
            label: state.mine == null ? '自愿登记展示名' : '修改或重新展示署名',
            onPressed: () => showHonorJoinDialog(context, ref),
          ),
          if (state.mine != null && !state.mine!.hidden)
            Mv2TextButton(
              label: '隐藏我的署名',
              onPressed: () async {
                final success = await ref
                    .read(honorsControllerProvider.notifier)
                    .hide();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? '署名已隐藏，Pro 权益不受影响' : '隐藏失败，请重试'),
                  ),
                );
              },
            ),
        ],
        const Text('署名为自愿公开展示，可修改或隐藏，不影响 Pro 权益。'),
      ],
    );
  }
}

/// 用户主动选择公开署名；不读取或绑定社区账号。
Future<void> showHonorJoinDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _HonorJoinDialog(),
  );
}

class _HonorJoinDialog extends ConsumerStatefulWidget {
  const _HonorJoinDialog();

  @override
  ConsumerState<_HonorJoinDialog> createState() => _HonorJoinDialogState();
}

class _HonorJoinDialogState extends ConsumerState<_HonorJoinDialog> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final mine = ref.read(honorsControllerProvider).value?.mine;
    _controller = TextEditingController(text: mine?.name ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(honorsControllerProvider.notifier)
          .join(_controller.text);
      if (!mounted) return;
      final message = switch (result) {
        HonorJoinResult.joined => '已永久铭刻在赞助榜，感谢支持！',
        HonorJoinResult.already => '你的名字已经在这面墙上了',
        HonorJoinResult.nameTaken => '这个名字已被使用，换一个吧',
        HonorJoinResult.notEntitled => '无法获取商店购买证明，请恢复购买后重试',
        HonorJoinResult.error => '登记失败，请稍后重试',
      };
      if (result != HonorJoinResult.joined &&
          result != HonorJoinResult.already) {
        setState(() => _error = message);
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('铭刻赞助榜'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: kMaxHonorNameLength,
        decoration: InputDecoration(
          labelText: '展示名',
          hintText: '公开展示的名字，可修改或隐藏',
          helperText: '自愿公开，不影响 Pro 权益',
          errorText: _error,
        ),
        onSubmitted: (_) => unawaited(_submit()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        Mv2TextButton(
          label: '铭刻',
          loading: _busy,
          onPressed: _busy ? null : () => unawaited(_submit()),
        ),
      ],
    );
  }
}
