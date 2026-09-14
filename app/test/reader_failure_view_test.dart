import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/reader/presentation/reader_failure_view.dart';

/// The reader's hard-failure surface is WebView-free, so it can be pumped
/// here: a page that never loaded shows 无法提取正文 with a browser escape.
void main() {
  testWidgets('failure view shows the error state and opens externally', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: ReaderFailureView(
            description: '网页加载失败，请检查网络后重试。',
            onOpenExternal: () => opened++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法提取正文'), findsOneWidget);
    expect(find.text('网页加载失败，请检查网络后重试。'), findsOneWidget);

    await tester.tap(find.text('用浏览器打开'));
    await tester.pump();
    expect(opened, 1);
  });
}
