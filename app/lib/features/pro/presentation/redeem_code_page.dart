import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/primitives/mv2_buttons.dart';
import '../../profile/application/app_promotion.dart';
import '../application/pro_controller.dart';

class RedeemCodePage extends ConsumerStatefulWidget {
  const RedeemCodePage({super.key});

  @override
  ConsumerState<RedeemCodePage> createState() => _RedeemCodePageState();
}

class _RedeemCodePageState extends ConsumerState<RedeemCodePage>
    with WidgetsBindingObserver {
  bool _waitingForStore = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForStore) {
      _waitingForStore = false;
      unawaited(_restore());
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final entitled = await ref.read(proControllerProvider.notifier).restore();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = entitled
          ? '永久版已解锁，感谢支持！'
          : ref.read(proControllerProvider).value?.errorMessage ??
                '暂未找到兑换记录。请确认使用同一个 Google Play 账号，兑换后可再次刷新。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final entitled = ref.watch(isProProvider);
    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(title: '兑换码', onBack: () => context.pop()),
      child: ListView(
        padding: const EdgeInsets.all(Mv2Spacing.x5),
        children: [
          Text(
            '兑换 MV2 永久版',
            style: context.text.topicTitleLarge.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: Mv2Spacing.x4),
          Text(
            '在 Google Play 的兑换页面输入收到的促销码。兑换成功后返回 MV2，即可同步永久版权益。请使用与购买时一致的 Google Play 账号。',
            style: context.text.bodySmall.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: Mv2Spacing.x5),
          if (entitled) ...[
            const Text('已拥有 MV2 永久版'),
            Mv2TextButton(
              label: '前往赞助榜',
              onPressed: () => context.push('/honors?source=redeem'),
            ),
          ] else ...[
            Mv2FilledButton(
              label: '前往 Google Play 兑换',
              onPressed: _busy
                  ? null
                  : () async {
                      _waitingForStore = true;
                      await AppPromotion.openPlayRedemption(context);
                    },
            ),
            Mv2TextButton(
              label: '已兑换，恢复权益',
              loading: _busy,
              onPressed: _busy ? null : _restore,
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: Mv2Spacing.x4),
              child: Text(_message!),
            ),
        ],
      ),
    );
  }
}
