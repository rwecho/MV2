import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/v2ex_endpoints.dart';
import '../../../core/solana/solana_keypair.dart';
import '../../../core/telemetry/mv2_analytics.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/solana_wallet_store.dart';

/// Sign in with Solana —— 钱包签名登录。
///
/// 与网页端 Phantom 扩展同一协议：本地对 `Sign in to V2EX: <unix 秒>` 做
/// ed25519 签名，`POST /auth/solana`（hex 签名 + 原文 + base58 公钥），
/// 会话 cookie 由响应直接种进 Dio 的 jar。私钥只在本机签名，不上传。
///
/// 「记住钱包」是 opt-in：私钥可以转走钱包全部资产，默认不落任何存储。
class SolanaLoginSheet extends ConsumerStatefulWidget {
  const SolanaLoginSheet({super.key});

  @override
  ConsumerState<SolanaLoginSheet> createState() => _SolanaLoginSheetState();
}

enum _SolanaStage { loadingWallet, wallet, input, submitting, notLinked }

class _SolanaLoginSheetState extends ConsumerState<SolanaLoginSheet> {
  final TextEditingController _secret = TextEditingController();
  bool _remember = false;
  bool _obscureSecret = true;
  _SolanaStage _stage = _SolanaStage.loadingWallet;
  String? _rememberedSecret;
  String? _rememberedAddress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRememberedWallet();
  }

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedWallet() async {
    final saved = await ref.read(solanaWalletStoreProvider).read();
    if (!mounted) return;
    setState(() {
      if (saved != null) {
        _rememberedSecret = saved.secretKey;
        _rememberedAddress = saved.address;
        _stage = _SolanaStage.wallet;
      } else {
        _stage = _SolanaStage.input;
      }
    });
  }

  Future<void> _submit() async {
    if (_stage == _SolanaStage.submitting) return;
    setState(() {
      _error = null;
      _stage = _SolanaStage.submitting;
    });

    final SolanaKeypair keypair;
    try {
      keypair = await SolanaKeypair.parse(
        _rememberedSecret ?? _secret.text,
      );
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _stage = _rememberedSecret == null
            ? _SolanaStage.input
            : _SolanaStage.wallet;
        _error = '无法识别的私钥格式。请粘贴 Phantom 导出的 base58 私钥。';
      });
      Mv2Analytics.logLoginSolanaSubmit(result: 'invalid_key');
      return;
    }

    try {
      // 服务端校验时间戳新鲜度（实测 ~400 `Message timestamp expired`），
      // 所以签名在提交瞬间生成，重试自动换新时间戳。
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final message = 'Sign in to V2EX: $timestamp';
      final signature = await keypair.signHex(message);
      final result = await ref
          .read(v2exApiProvider)
          .loginWithSolana(
            publicKey: keypair.address,
            signature: signature,
            message: message,
          );
      if (!mounted) return;

      if (result.success) {
        if (_remember && _rememberedSecret == null) {
          await ref
              .read(solanaWalletStoreProvider)
              .write(secretKey: _secret.text.trim(), address: keypair.address);
        }
        await ref.read(authControllerProvider.notifier).refreshAccount();
        if (!mounted) return;
        final signedIn =
            ref.read(authControllerProvider).value?.isSignedIn ?? false;
        if (!signedIn) {
          setState(() {
            _stage = _SolanaStage.input;
            _error = '登录未完成，请重试。';
          });
          Mv2Analytics.logLoginSolanaSubmit(result: 'failed');
          return;
        }
        Mv2Analytics.logLoginSolanaSubmit(result: 'success');
        Navigator.of(context).pop();
        if (mounted) context.pop();
        return;
      }

      if (!result.walletLinked) {
        setState(() => _stage = _SolanaStage.notLinked);
        Mv2Analytics.logLoginSolanaSubmit(result: 'not_linked');
        return;
      }
      setState(() {
        _stage = _rememberedSecret == null
            ? _SolanaStage.input
            : _SolanaStage.wallet;
        _error = result.serverError ?? '登录失败，请重试。';
      });
      Mv2Analytics.logLoginSolanaSubmit(result: 'failed');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _SolanaStage.input;
        _error = error is Failure ? error.message : '登录失败：$error';
      });
      Mv2Analytics.logLoginSolanaSubmit(result: 'failed');
    }
  }

  Future<void> _forgetWallet() async {
    await ref.read(solanaWalletStoreProvider).clear();
    if (!mounted) return;
    setState(() {
      _rememberedSecret = null;
      _remember = false;
      _stage = _SolanaStage.input;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Mv2Spacing.pageNarrow,
          Mv2Spacing.x4,
          Mv2Spacing.pageNarrow,
          Mv2Spacing.x8,
        ),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '使用 Solana 钱包登录',
                  style: context.text.topicTitleLarge.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: Mv2Spacing.x2),
          Text(
            '对登录消息做钱包签名即可登录，私钥只在本机签名，不会上传。',
            style: context.text.bodySmall.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: Mv2Spacing.x5),
          switch (_stage) {
            _SolanaStage.loadingWallet => const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            _SolanaStage.wallet => _walletView(context),
            _SolanaStage.input ||
            _SolanaStage.submitting => _inputView(context),
            _SolanaStage.notLinked => _notLinkedView(context),
          },
          if (_error != null) ...<Widget>[
            const SizedBox(height: Mv2Spacing.x3),
            _errorBanner(context, _error!),
          ],
        ],
      ),
    );
  }

  /// 已保存钱包：一键签名登录。
  Widget _walletView(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(Mv2Spacing.x3),
          decoration: BoxDecoration(
            color: colors.divider,
            borderRadius: Mv2Radius.allSm,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: <Widget>[
              Image.asset(
                'assets/auth/solana.png',
                width: 28,
                height: 28,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              const SizedBox(width: Mv2Spacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '已保存的钱包',
                      style: context.text.metadata.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                    Text(
                      _rememberedAddress ?? '',
                      style: context.text.body.copyWith(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Mv2Spacing.x4),
        _primaryButton(
          context,
          label: '签名并登录',
          onTap: _submit,
        ),
        const SizedBox(height: Mv2Spacing.x3),
        Row(
          children: <Widget>[
            Expanded(
              child: _secondaryButton(context, label: '换一个钱包', onTap: () {
                setState(() {
                  _rememberedSecret = null;
                  _stage = _SolanaStage.input;
                });
              }),
            ),
            const SizedBox(width: Mv2Spacing.x3),
            Expanded(
              child: _secondaryButton(
                context,
                label: '忘记此钱包',
                onTap: _forgetWallet,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 输入私钥。
  Widget _inputView(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _secret,
          enabled: _stage != _SolanaStage.submitting,
          obscureText: _obscureSecret,
          autocorrect: false,
          enableSuggestions: false,
          maxLines: 1,
          decoration: InputDecoration(
            hintText: 'Solana 私钥（base58）',
            suffixIcon: IconButton(
              icon: Icon(
                _obscureSecret
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscureSecret = !_obscureSecret),
            ),
          ),
          style: context.text.body.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: Mv2Spacing.x1),
        Text(
          '支持 Phantom / Solflare 导出的 64 字节 base58 私钥（或 32 字节种子）。',
          style: context.text.metadata.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: Mv2Spacing.x3),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '在这台设备上记住钱包（私钥存入系统安全存储）',
                style: context.text.metadata.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            Switch.adaptive(
              value: _remember,
              activeTrackColor: colors.accent,
              onChanged: (value) => setState(() => _remember = value),
            ),
          ],
        ),
        const SizedBox(height: Mv2Spacing.x4),
        _primaryButton(
          context,
          label: _stage == _SolanaStage.submitting ? null : '签名并登录',
          onTap: _stage == _SolanaStage.submitting ? () {} : _submit,
        ),
      ],
    );
  }

  /// 签名有效但钱包未绑定 V2EX 账号 —— 网页端对应跳 `/solana/signup`。
  Widget _notLinkedView(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(Mv2Spacing.x3),
          decoration: BoxDecoration(
            color: colors.divider,
            borderRadius: Mv2Radius.allSm,
            border: Border.all(color: colors.border),
          ),
          child: Text(
            '该钱包尚未绑定 V2EX 账号。请先在网页端登录并绑定钱包，'
            '或通过 v2ex.com/solana 用钱包注册新账号，然后回来重新登录。',
            style: context.text.body.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(height: Mv2Spacing.x4),
        _primaryButton(
          context,
          label: '打开 v2ex.com/solana 绑定',
          onTap: () => launchUrl(
            Uri.parse('${V2exEndpoints.baseUrl}${V2exEndpoints.solanaHelp}'),
            mode: LaunchMode.externalApplication,
          ),
        ),
        const SizedBox(height: Mv2Spacing.x3),
        _secondaryButton(
          context,
          label: '重新检查',
          onTap: () => setState(() {
            _stage = _rememberedSecret == null
                ? _SolanaStage.input
                : _SolanaStage.wallet;
            _error = null;
          }),
        ),
      ],
    );
  }

  Widget _errorBanner(BuildContext context, String message) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.error_outline_rounded, size: 16, color: colors.danger),
        const SizedBox(width: Mv2Spacing.x2),
        Expanded(
          child: Text(
            message,
            style: context.text.metadata.copyWith(color: colors.danger),
          ),
        ),
      ],
    );
  }

  Widget _primaryButton(
    BuildContext context, {
    String? label,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return SizedBox(
      height: 48,
      child: Material(
        color: colors.accent,
        borderRadius: Mv2Radius.allSm,
        child: InkWell(
          borderRadius: Mv2Radius.allSm,
          onTap: onTap,
          child: Center(
            child: label == null
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colors.accentContrast,
                      ),
                    ),
                  )
                : Text(
                    label,
                    style: context.text.button.copyWith(
                      color: colors.accentContrast,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return SizedBox(
      height: 44,
      child: Material(
        color: Colors.transparent,
        borderRadius: Mv2Radius.allSm,
        child: InkWell(
          borderRadius: Mv2Radius.allSm,
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: Mv2Radius.allSm,
              border: Border.all(color: colors.border),
            ),
            child: Text(
              label,
              style: context.text.button.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
