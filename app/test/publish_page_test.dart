import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/composer/presentation/publish_topic_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_container.dart';
import 'package:mv2/core/data/v2ex_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [v2exApiProvider.overrideWithValue(fixtureApi())],
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const PublishTopicPage(),
        ),
      ),
    );
    // Post-frame init, then the fixture API's 250ms latency.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('renders the node selector, title and content fields', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('发布主题'), findsOneWidget);
    expect(find.text('发布'), findsOneWidget);
    // `/new` fixture preselects 程序员.
    expect(find.text('程序员'), findsOneWidget);
    expect(find.text('/go/programmer'), findsOneWidget);
    expect(find.text('填写标题'), findsOneWidget);
    expect(find.text('写下正文，支持 Markdown...'), findsOneWidget);
    expect(find.text('草稿未保存'), findsOneWidget);
  });

  testWidgets('typing enables 发布 and marks the draft saved', (tester) async {
    await pumpPage(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Flutter 迁移记录');
    await tester.enterText(fields.at(1), '正文内容');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(find.text('草稿已保存'), findsOneWidget);
  });

  testWidgets('预览 renders the Markdown draft', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField).at(1), '**加粗**正文');
    await tester.pump();
    await tester.tap(find.text('预览'));
    await tester.pump();

    // The editor is replaced by the rendered pane.
    expect(find.text('写下正文，支持 Markdown...'), findsNothing);
    expect(find.text('编辑'), findsOneWidget);
    // `Mv2RichText` renders the strong run as its own Text span.
    expect(find.textContaining('加粗'), findsOneWidget);
  });
}
