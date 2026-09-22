import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/telemetry/mv2_analytics.dart';
import 'package:mv2/features/profile/application/app_promotion.dart';

/// 「我的」页推广动作的平台门控与兜底路径。
///
/// 测试宿主是桌面（非 iOS/Android），正好覆盖「无商店平台」分支：商店
/// 专属入口应隐藏，动作落到 GitHub 并按各自事件名埋点。iOS/Android 分支
/// 依赖平台商店，模拟器/真机验证，测试不覆盖。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async => true,
    );
  });

  final events = <String, List<Map<String, Object?>>>{};
  setUp(() {
    events.clear();
    Mv2Analytics.sink = (event, params) =>
        (events[event] ??= <Map<String, Object?>>[]).add(params);
  });
  tearDown(() => Mv2Analytics.sink = null);

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    BuildContext? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return captured!;
  }

  test('无商店平台不显示商店专属入口', () {
    expect(AppPromotion.onStorePlatform, isFalse);
  });

  testWidgets('给个好评在无商店平台走 GitHub 兜底并记 method=github', (tester) async {
    await AppPromotion.requestReview(await pumpHost(tester));
    expect(events['app_review'], <Map<String, Object?>>[
      {'method': 'github'},
    ]);
  });

  testWidgets('兑换码在无商店平台同样兜底到 GitHub', (tester) async {
    await AppPromotion.openRedeem(await pumpHost(tester));
    expect(events['app_redeem'], hasLength(1));
  });
}
