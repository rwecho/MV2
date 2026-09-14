import 'package:flutter/material.dart';

import '../../../design_system/theme/mv2_theme.dart';
import '../../../ui/components/states/mv2_state_view.dart';

/// The reader page's hard-failure surface: the page itself could not be loaded
/// (network / bad URL), so there is no 原文 to fall back to either.
///
/// Split out of `reader_page.dart` so it can be pumped in `flutter test`
/// without a WebView. Extraction-only failures are *not* shown here — those
/// fall back to 原文 with a notice.
class ReaderFailureView extends StatelessWidget {
  const ReaderFailureView({
    super.key,
    required this.description,
    required this.onOpenExternal,
  });

  final String description;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background,
      child: Mv2StateView(
        kind: Mv2StateKind.error,
        title: '无法提取正文',
        description: description,
        actionLabel: '用浏览器打开',
        onAction: onOpenExternal,
      ),
    );
  }
}
