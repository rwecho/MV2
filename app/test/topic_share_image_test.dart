import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/topic/presentation/topic_share_image.dart';
import 'support/fixture_api.dart';

/// 分享长图卡片（TopicShareCard）的版面契约：标题/作者/正文/页脚齐全，
/// 页脚带话题链接。生成（Overlay 截图）依赖真机渲染与平台分享通道，测试
/// 不覆盖——真机验证。
void main() {
  testWidgets('卡片版面：标题、作者、正文与页脚链接', (tester) async {
    final detail = await FixtureV2exApi(
      latency: Duration.zero,
    ).topicDetail(1);

    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              child: TopicShareCard(detail: detail),
            ),
          ),
        ),
      ),
    );
    // 定时 pump 而非 pumpAndSettle：正文里的网络图在测试里永不解析。
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(detail.topic.title), findsOneWidget);
    expect(find.text('@${detail.topic.author.username}'), findsOneWidget);
    expect(find.text('MV2 · 更好的 V2EX 客户端'), findsOneWidget);
    expect(
      find.textContaining('https://www.v2ex.com/t/1'),
      findsOneWidget,
    );
  });
}
