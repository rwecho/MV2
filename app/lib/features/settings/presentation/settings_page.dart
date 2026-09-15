import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/push/push_providers.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/mv2_settings_row.dart';
import '../application/settings_controller.dart';
import '../application/settings_providers.dart';

/// `设置` — `designs/08-settings.png`.
///
/// A full-screen destination (the shell hides the floating tab bar here), so
/// the scaffold gets no bottom bar and needs no tab-content inset.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(title: '设置', onBack: () => context.pop()),
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
            // ----------------------------------------------------- 外观
            Mv2SettingsGroup(
              badge: '外观',
              children: <Widget>[
                Mv2SettingsRow(
                  label: '主题',
                  icon: Icons.wb_sunny_outlined,
                  value: settings.colorMode.label,
                  onTap: () => _showSelectionSheet<Mv2ColorMode>(
                    context: context,
                    title: '主题',
                    options: Mv2ColorMode.values,
                    selected: settings.colorMode,
                    labelOf: (Mv2ColorMode mode) => mode.label,
                    onSelected: notifier.setColorMode,
                  ),
                ),
                Mv2SettingsRow(
                  label: '字体大小',
                  leadingText: 'AA',
                  value: settings.fontSize.label,
                  onTap: () => _showSelectionSheet<Mv2FontSize>(
                    context: context,
                    title: '字体大小',
                    options: Mv2FontSize.values,
                    selected: settings.fontSize,
                    labelOf: (Mv2FontSize size) => size.label,
                    onSelected: notifier.setFontSize,
                  ),
                ),
                Mv2SettingsRow(
                  label: '内容宽度',
                  icon: Icons.crop_landscape_rounded,
                  value: settings.contentWidth.label,
                  onTap: () => _showSelectionSheet<Mv2ContentWidth>(
                    context: context,
                    title: '内容宽度',
                    options: Mv2ContentWidth.values,
                    selected: settings.contentWidth,
                    labelOf: (Mv2ContentWidth width) => width.label,
                    onSelected: notifier.setContentWidth,
                  ),
                  showDivider: false,
                ),
              ],
            ),

            // ----------------------------------------------------- 阅读
            Mv2SettingsGroup(
              badge: '阅读',
              children: <Widget>[
                Mv2SettingsRow(
                  label: '外链打开方式',
                  icon: Icons.open_in_new_rounded,
                  value: settings.openLinkMode.label,
                  onTap: () => _showSelectionSheet<Mv2LinkOpenMode>(
                    context: context,
                    title: '外链打开方式',
                    options: Mv2LinkOpenMode.values,
                    selected: settings.openLinkMode,
                    labelOf: (Mv2LinkOpenMode mode) => mode.label,
                    onSelected: notifier.setOpenLinkMode,
                  ),
                ),
                Mv2SettingsRow(
                  label: '自动折叠长回复',
                  icon: Icons.notes_rounded,
                  description: '超过一定长度的回复将自动折叠',
                  showChevron: false,
                  trailing: Switch(
                    value: settings.autoCollapseReplies,
                    onChanged: notifier.setAutoCollapseReplies,
                  ),
                  showDivider: false,
                ),
              ],
            ),

            // ----------------------------------------------------- 交互
            Mv2SettingsGroup(
              badge: '交互',
              children: <Widget>[
                Mv2SettingsRow(
                  label: '触觉反馈',
                  icon: Icons.vibration_rounded,
                  description: '在操作时提供触感反馈',
                  showChevron: false,
                  trailing: Switch(
                    value: settings.hapticsEnabled,
                    onChanged: notifier.setHapticsEnabled,
                  ),
                ),
                Mv2SettingsRow(
                  label: '推送通知',
                  icon: Icons.notifications_active_outlined,
                  description: '回复、提及、收藏与感谢提醒',
                  showChevron: false,
                  trailing: Switch(
                    value: settings.pushEnabled,
                    onChanged: (value) => _setPushEnabled(ref, value),
                  ),
                ),
                Mv2SettingsRow(
                  label: '默认回复排序',
                  icon: Icons.sort_rounded,
                  value: settings.replySort.label,
                  onTap: () => _showSelectionSheet<Mv2ReplySort>(
                    context: context,
                    title: '默认回复排序',
                    options: Mv2ReplySort.values,
                    selected: settings.replySort,
                    labelOf: (Mv2ReplySort sort) => sort.label,
                    onSelected: notifier.setReplySort,
                  ),
                  showDivider: false,
                ),
              ],
            ),

            // ------------------------------------------------ 缓存与数据
            Mv2SettingsGroup(
              badge: '缓存与数据',
              children: <Widget>[
                Mv2SettingsRow(
                  label: '清除缓存',
                  icon: Icons.delete_outline_rounded,
                  value: _formatCacheSize(ref.watch(cacheSizeProvider)),
                  onTap: () async {
                    final confirmed = await _confirm(
                      context: context,
                      title: '清除缓存',
                      message: '将清除本地缓存的页面数据，确定继续吗？',
                      confirmLabel: '清除',
                    );
                    if (!confirmed || !context.mounted) return;
                    await ref.read(httpCacheProvider).clear();
                    ref.invalidate(cacheSizeProvider);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('缓存已清除')));
                  },
                ),
                Mv2SettingsRow(
                  label: '浏览历史',
                  icon: Icons.history_rounded,
                  onTap: () => context.push('/history'),
                  showDivider: false,
                ),
              ],
            ),

            // ----------------------------------------------------- 隐私
            Mv2SettingsGroup(
              badge: '隐私',
              children: <Widget>[
                Mv2SettingsRow(
                  label: '屏蔽用户',
                  icon: Icons.person_off_outlined,
                  onTap: () => context.push('/blocked-users'),
                ),
                Mv2SettingsRow(
                  label: '数据删除',
                  icon: Icons.delete_forever_outlined,
                  onTap: () => _confirmDataDeletion(context),
                  showDivider: false,
                ),
              ],
            ),

            // ----------------------------------------------------- 关于
            Mv2SettingsGroup(
              badge: '关于',
              children: <Widget>[
                Mv2SettingsRow(
                  label: '关于 MV2',
                  icon: Icons.info_outline_rounded,
                  onTap: () => context.push('/about'),
                ),
                Mv2SettingsRow(
                  label: '当前版本',
                  icon: Icons.new_releases_outlined,
                  value: ref.watch(appVersionProvider).value ?? '…',
                  showChevron: false,
                ),
                Mv2SettingsRow(
                  label: 'GitHub',
                  icon: Icons.code_rounded,
                  onTap: () => _openExternal(_githubUrl),
                ),
                Mv2SettingsRow(
                  label: '隐私政策',
                  icon: Icons.privacy_tip_outlined,
                  onTap: () => _openExternal(_privacyUrl),
                  showDivider: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- helpers

/// Project repository and the two policy pages published from it.
const String _githubUrl = 'https://github.com/rwecho/V2ex.Maui2';
const String _privacyUrl = 'https://rwecho.github.io/MV2/privacy.html';
const String _deletionUrl = 'https://rwecho.github.io/MV2/deletion.html';

/// Opens an external page in the OS browser (never an in-app webview).
Future<void> _openExternal(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Flips 推送通知 and syncs the device with the push worker.
///
/// Enabling asks for the OS permission (and, if the account has visited the
/// notifications page before, re-registers immediately); disabling unregisters
/// so the worker stops polling this account. Both halves are best-effort — the
/// switch reflects the local preference even when the network call fails.
void _setPushEnabled(WidgetRef ref, bool value) {
  unawaited(ref.read(settingsProvider.notifier).setPushEnabled(value));
  final push = ref.read(pushServiceProvider);
  unawaited(value ? push.register() : push.unregister());
}

/// 数据删除 explains the browser hand-off before leaving the app.
Future<void> _confirmDataDeletion(BuildContext context) async {
  final confirmed = await _confirm(
    context: context,
    title: '数据删除',
    message: '将打开浏览器前往数据删除说明页面，确定继续吗？',
    confirmLabel: '打开',
  );
  if (!confirmed) return;
  await _openExternal(_deletionUrl);
}

/// Presents a token-styled single-choice bottom sheet.
Future<void> _showSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T option) labelOf,
  required ValueChanged<T> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.elevatedSurface,
    shape: const RoundedRectangleBorder(borderRadius: Mv2Radius.allXl),
    builder: (BuildContext sheetContext) => _SelectionSheet<T>(
      title: title,
      options: options,
      selected: selected,
      labelOf: labelOf,
      onSelected: onSelected,
    ),
  );
}

/// Confirmation dialog; resolves to `false` when dismissed.
/// Human-readable cache size for the 清除缓存 row.
String _formatCacheSize(AsyncValue<int> value) {
  return value.when(
    data: (bytes) {
      if (bytes <= 0) return '0 KB';
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    },
    loading: () => '计算中',
    error: (_, _) => '—',
  );
}

Future<bool> _confirm({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final colors = dialogContext.colors;
      return AlertDialog(
        backgroundColor: colors.elevatedSurface,
        shape: const RoundedRectangleBorder(borderRadius: Mv2Radius.allXl),
        title: Text(
          title,
          style: dialogContext.text.sectionTitle.copyWith(
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          message,
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
              confirmLabel,
              style: dialogContext.text.button.copyWith(color: colors.danger),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Sheet body: title + one row per option, with a check mark on the selection.
class _SelectionSheet<T> extends StatelessWidget {
  const _SelectionSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String title;
  final List<T> options;
  final T selected;
  final String Function(T option) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Mv2Spacing.x4,
              Mv2Spacing.x5,
              Mv2Spacing.x4,
              Mv2Spacing.x2,
            ),
            child: Text(
              title,
              style: context.text.sectionTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          for (final T option in options)
            _SelectionOption(
              label: labelOf(option),
              selected: option == selected,
              onTap: () {
                Navigator.of(context).pop();
                onSelected(option);
              },
            ),
          const SizedBox(height: Mv2Spacing.x3),
        ],
      ),
    );
  }
}

class _SelectionOption extends StatelessWidget {
  const _SelectionOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Mv2Spacing.minTapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: Mv2Spacing.x4,
          vertical: Mv2Spacing.x3,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: context.text.body.copyWith(
                  color: selected ? colors.accent : colors.textPrimary,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 20, color: colors.accent),
          ],
        ),
      ),
    );
  }
}
