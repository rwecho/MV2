import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/telemetry/mv2_analytics.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_rich_text.dart';

/// Base64 点击解码（联系方式防爬虫场景，V2EX Polish 同款）：正文里的
/// base64 串出现「解码」徽章，点串或徽章弹层展示明文并可复制。
Future<void> pumpBody(WidgetTester tester, String html) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: Mv2ThemeData.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 300, child: Mv2RichText(html: html)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final events = <String, List<Map<String, Object?>>>{};
  setUp(() {
    events.clear();
    Mv2Analytics.sink = (event, params) =>
        (events[event] ??= <Map<String, Object?>>[]).add(params);
  });
  tearDown(() => Mv2Analytics.sink = null);

  testWidgets('正文里的 base64 出现解码徽章，点开弹层展示中文明文', (tester) async {
    const plaintext = '微信：mv2-fans，备注 V2EX';
    final cipher = base64.encode(utf8.encode(plaintext));
    await pumpBody(tester, '<p>联系方式：$cipher</p>');

    expect(find.text('解码'), findsOneWidget);

    await tester.tap(find.text('解码'));
    await tester.pumpAndSettle();

    expect(find.text('Base64 解码'), findsOneWidget);
    expect(find.text(plaintext), findsOneWidget);
    expect(events['base64_tool'], <Map<String, Object?>>[
      {'action': 'decode'},
    ]);
  });

  testWidgets('普通文本不出现解码徽章', (tester) async {
    await pumpBody(tester, '<p>abcdefghijklmnop</p>');
    expect(find.text('解码'), findsNothing);
  });
}
