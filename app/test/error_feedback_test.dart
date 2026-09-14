import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/ui/components/mv2_error_feedback.dart';
import 'package:mv2/ui/components/mv2_refreshable.dart';

void main() {
  group('mv2DescribeError', () {
    test('prefers the Failure message', () {
      expect(mv2DescribeError(const NetworkFailure()), '网络连接失败，请检查网络后重试。');
      expect(mv2DescribeError(const AuthFailure()), '登录状态已失效，请重新登录。');
    });

    test('falls back for unknown errors', () {
      expect(mv2DescribeError(StateError('boom')), '出错了，请稍后重试。');
    });
  });

  testWidgets('a failed pull-to-refresh shows a toast', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: Mv2ThemeData.light(),
        home: Scaffold(
          body: Mv2Refreshable(
            onRefresh: () async => throw const NetworkFailure(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const <Widget>[SizedBox(height: 2000)],
            ),
          ),
        ),
      ),
    );

    // Pull down from the top to trigger the refresh indicator.
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('网络连接失败，请检查网络后重试。'), findsOneWidget);
  });
}
