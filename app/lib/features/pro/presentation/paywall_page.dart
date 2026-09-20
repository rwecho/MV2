import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../application/honors_controller.dart';
import '../application/pro_backend.dart';
import '../application/pro_controller.dart';
import 'honor_wall_page.dart';

/// 付费墙：永久买断（非消耗型内购）。
///
/// 骨架阶段不门控任何功能 —— 这一页负责完整的商业闭环：拉取商店价格 →
/// 购买 → 权益持久化 → 恢复购买。后续功能门控统一读 [isProProvider]。
class PaywallPage extends ConsumerStatefulWidget {
  const PaywallPage({super.key, this.source = 'settings'});

  /// 归因参数（`paywall_open.source`）。
  final String source;

  @override
  ConsumerState<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends ConsumerState<PaywallPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Mv2Analytics.logPaywallOpen(source: widget.source);
  }

  Future<void> _purchase() async {
    if (_busy) return;
    setState(() => _busy = true);
    ProPurchaseOutcome outcome;
    try {
      outcome = await ref.read(proControllerProvider.notifier).purchase();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    switch (outcome) {
      case ProPurchaseOutcome.success:
        _toast('已解锁永久版，感谢支持！');
      case ProPurchaseOutcome.cancelled:
        return;
      case ProPurchaseOutcome.pending:
        _toast('支付确认中，商店批准后自动解锁');
        return;
      case ProPurchaseOutcome.error:
        _toast('购买未完成，请稍后重试');
        return;
    }
    if (!mounted) return;
    // 购买成功是登记赞助榜的最佳时机（服务端会再核验权益）。
    final joined = ref.read(honorsControllerProvider).value?.joined ?? false;
    if (!joined) unawaited(showHonorJoinDialog(context, ref));
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final entitled = await ref.read(proControllerProvider.notifier).restore();
      if (!mounted) return;
      _toast(entitled ? '已恢复永久版权益' : '此账号下没有可恢复的购买');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pro = ref.watch(proControllerProvider);

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(title: '赞助 MV2', onBack: () => context.pop()),
      child: pro.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Mv2StateView(
          kind: Mv2StateKind.error,
          description: '商店信息加载失败',
          actionLabel: '重试',
          onAction: () => ref.invalidate(proControllerProvider),
        ),
        data: (state) => _Body(
          state: state,
          busy: _busy,
          onBuy: _purchase,
          onRestore: _restore,
          onRetry: () => ref.invalidate(proControllerProvider),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.busy,
    required this.onBuy,
    required this.onRestore,
    required this.onRetry,
  });

  final ProState state;
  final bool busy;
  final Future<void> Function() onBuy;
  final Future<void> Function() onRestore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.entitled) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Mv2StateView(
            kind: Mv2StateKind.empty,
            title: '已赞助 MV2',
            description: '一次买断，永久有效。感谢支持！',
          ),
          const SizedBox(height: Mv2Spacing.x4),
          Mv2TextButton(
            label: '看看赞助榜',
            onPressed: () => context.push('/honors?source=paywall'),
          ),
        ],
      );
    }

    if (!state.configured) {
      // 只有缺公钥的构建才会走到这里（本地开发 / CI）。
      return const Mv2StateView(
        kind: Mv2StateKind.error,
        title: '商店尚未配置',
        description: '此构建未接入应用商店，暂时无法购买。',
      );
    }

    final product = state.product;
    if (product == null) {
      return Mv2StateView(
        kind: Mv2StateKind.error,
        description: '暂时拿不到商品信息',
        actionLabel: '重试',
        onAction: onRetry,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Mv2Spacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(
            Icons.workspace_premium_rounded,
            size: 72,
            color: context.colors.accent,
          ),
          const SizedBox(height: Mv2Spacing.x4),
          Text(
            '赞助 MV2 开发',
            textAlign: TextAlign.center,
            style: context.text.topicTitleLarge.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: Mv2Spacing.x2),
          Text(
            '一次买断 · 永久有效 · 支持本机商店账号恢复',
            textAlign: TextAlign.center,
            style: context.text.bodySmall.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: Mv2Spacing.x6),
          Mv2TextButton(
            label: '赞助 ${product.price}',
            loading: busy,
            onPressed: busy ? null : onBuy,
          ),
          const SizedBox(height: Mv2Spacing.x2),
          Mv2TextButton(label: '恢复购买', enabled: !busy, onPressed: onRestore),
          const SizedBox(height: Mv2Spacing.x5),
          Text(
            '通过 App Store / Google Play 结算，购买绑定你的商店账号，'
            '换机或重装后可在本页恢复。',
            textAlign: TextAlign.center,
            style: context.text.metadata.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
