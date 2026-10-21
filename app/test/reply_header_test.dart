import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/ui/components/mv2_reply_header.dart';

void main() {
  test('compact time preserves device and unfamiliar labels', () {
    expect(mv2CompactReplyTime('22 小时 59 分钟前 via iPhone'), '22小时前 via iPhone');
    expect(mv2CompactReplyTime('5 分钟 12 秒前 via Android'), '5分钟前 via Android');
    expect(mv2CompactReplyTime('刚刚'), '刚刚');
    expect(
      mv2CompactReplyTime('2026-10-20 via Android'),
      '2026-10-20 via Android',
    );
  });

  testWidgets(
    'compresses only when needed and restores full metadata on resize',
    (tester) async {
      final seen = <String>{};
      Future<void> pump(
        double width, {
        double scale = 1,
        String name = 'my2492',
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: Mv2ThemeData.light(),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: Mv2ReplyHeader(
                      reply: V2Reply(
                        floor: 1,
                        author: V2User(username: name),
                        content: '',
                        createdAtLabel: '22 小时 59 分钟前 via iPhone',
                        badges: const ['OP'],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.text('@$name')).width, greaterThan(0));
      }

      for (var width = 600.0; width >= 160; width -= 2) {
        await pump(width);
        final texts = tester.widgetList<Text>(find.byType(Text));
        seen.add(texts.firstWhere((text) => text.data!.startsWith('#1')).data!);
      }
      expect(
        seen,
        containsAll([
          '#1 · 22 小时 59 分钟前 via iPhone',
          '#1 · 22小时前 via iPhone',
          '#1 · 22小时前 · iPhone',
        ]),
      );
      await pump(240, scale: 2, name: 'an_extremely_long_username');
      await pump(600);
      expect(find.text('#1 · 22 小时 59 分钟前 via iPhone'), findsOneWidget);
      await pump(160);
      await tester.tap(find.byType(Tooltip));
      await tester.pump();
      expect(find.text('#1 · 22 小时 59 分钟前 via iPhone'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
