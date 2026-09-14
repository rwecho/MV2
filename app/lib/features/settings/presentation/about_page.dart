import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../design_system/effects/mv2_glass.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_settings_row.dart';
import '../application/settings_providers.dart';

/// 关于 MV2 — app identity plus the project's policy links.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final appVersion = ref.watch(appVersionProvider).value ?? '…';

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(title: '关于 MV2', onBack: () => context.pop()),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Mv2Spacing.pageNarrow,
          0,
          Mv2Spacing.pageNarrow,
          Mv2Spacing.x8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ------------------------------------------------- 应用标识
            Padding(
              padding: const EdgeInsets.only(top: Mv2Spacing.x6),
              child: Column(
                children: <Widget>[
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: Mv2Radius.allLg,
                    ),
                    child: Icon(
                      Icons.code_rounded,
                      size: 32,
                      color: colors.accentContrast,
                    ),
                  ),
                  const SizedBox(height: Mv2Spacing.x4),
                  Text(
                    'MV2',
                    style: context.text.pageTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '版本 $appVersion',
                    style: context.text.metadata.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Mv2Spacing.x4),
                  Text(
                    'MV2 是一个面向移动端的 V2EX 第三方客户端',
                    textAlign: TextAlign.center,
                    style: context.text.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Mv2Spacing.x2),
                  Text(
                    '内容与数据来自 V2EX 与 sov2ex（非官方客户端）',
                    textAlign: TextAlign.center,
                    style: context.text.metadata.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // ----------------------------------------------------- 相关链接
            Mv2SettingsGroup(
              badge: '相关链接',
              children: <Widget>[
                Mv2SettingsRow(
                  label: 'GitHub',
                  icon: Icons.code_rounded,
                  onTap: () => _openExternal(_githubUrl),
                ),
                Mv2SettingsRow(
                  label: '隐私政策',
                  icon: Icons.privacy_tip_outlined,
                  onTap: () => _openExternal(_privacyUrl),
                ),
                Mv2SettingsRow(
                  label: '数据删除',
                  icon: Icons.delete_forever_outlined,
                  onTap: () => _confirmDeletion(context),
                  showDivider: false,
                ),
              ],
            ),

            // ------------------------------------------ 数据来源（仅调试）
            if (kDebugMode) ...<Widget>[
              const SizedBox(height: Mv2Spacing.x6),
              Text(
                '数据来源 / 版本',
                style: context.text.metadata.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: Mv2Spacing.x2),
              Mv2Surface(
                borderRadius: Mv2Radius.allMd,
                shadowed: false,
                padding: const EdgeInsets.all(Mv2Spacing.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const _DebugLine(label: '数据来源', value: 'V2EX · sov2ex'),
                    const SizedBox(height: Mv2Spacing.x2),
                    _DebugLine(label: '版本', value: appVersion),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- helpers

/// Repository and the two policy pages published from it.
const String _githubUrl = 'https://github.com/rwecho/V2ex.Maui2';
const String _privacyUrl = 'https://rwecho.github.io/V2ex.Maui2/privacy.html';
const String _deletionUrl = 'https://rwecho.github.io/V2ex.Maui2/deletion.html';

/// Opens an external page in the OS browser (never an in-app webview).
Future<void> _openExternal(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// 数据删除 explains the browser hand-off before leaving the app.
Future<void> _confirmDeletion(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final colors = dialogContext.colors;
      return AlertDialog(
        backgroundColor: colors.elevatedSurface,
        shape: const RoundedRectangleBorder(borderRadius: Mv2Radius.allXl),
        title: Text(
          '数据删除',
          style: dialogContext.text.sectionTitle.copyWith(
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          '将打开浏览器前往数据删除说明页面，确定继续吗？',
          style: dialogContext.text.bodySmall.copyWith(
            color: colors.textSecondary,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              '取消',
              style: dialogContext.text.button.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '打开',
              style: dialogContext.text.button.copyWith(color: colors.danger),
            ),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;
  await _openExternal(_deletionUrl);
}

/// Quiet label/value line used only by the debug source block.
class _DebugLine extends StatelessWidget {
  const _DebugLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: <Widget>[
        Text(
          label,
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: context.text.metadata.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}
