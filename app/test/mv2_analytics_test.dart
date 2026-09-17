import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/telemetry/mv2_analytics.dart';
import 'package:mv2/core/telemetry/mv2_events.dart';

/// sink 捕获测试。`flutter test` 没有 Firebase 配置,`Mv2Telemetry.isReady`
/// 恒为 false — 这正是 sink 存在的理由:它必须绕过就绪门控照常触发,
/// 否则埋点在测试里完全不可观测。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final captured = <({String event, Map<String, Object?> params})>[];

  setUp(() {
    captured.clear();
    Mv2Analytics.sink = (event, params) =>
        captured.add((event: event, params: Map.of(params)));
  });

  tearDown(() {
    // 泄漏的 sink 会捕获同一 VM 里后续测试文件的事件。
    Mv2Analytics.sink = null;
  });

  test('未就绪时埋点是安静 no-op(不抛异常)', () {
    expect(
      () => Mv2Analytics.logTopicOpen(
        topicId: 1,
        source: 'feed',
        layout: 'phone',
      ),
      returnsNormally,
    );
  });

  test('screen_view 经 sink 捕获并携带模板化页面名', () {
    Mv2Analytics.logScreenView(screenName: '/topic/:id');

    expect(captured.single.event, Mv2Events.screenView);
    expect(captured.single.params, {'screen_name': '/topic/:id'});
  });

  test('sink 捕获到精确的事件名与参数', () {
    Mv2Analytics.logTopicOpen(
      topicId: 9527,
      source: 'search',
      layout: 'tablet',
    );

    expect(captured, hasLength(1));
    expect(captured.single.event, Mv2Events.topicOpen);
    expect(captured.single.params, {
      'topic_id': 9527,
      'source': 'search',
      'layout': 'tablet',
    });
  });

  test('无参事件同样可捕获', () {
    Mv2Analytics.logLoginOpen();

    expect(captured.single.event, Mv2Events.loginOpen);
    expect(captured.single.params, isEmpty);
  });

  test('字符串参数截断到 100 字符(Firebase 硬限制)', () {
    Mv2Analytics.logSettingChange(key: 'k', value: 'v' * 150);

    expect(captured.single.params['value'], 'v' * 100);
  });

  test('长度/体积分桶在发送前完成', () {
    Mv2Analytics.logReplySubmit(
      topicId: 1,
      hasQuote: true,
      contentLength: 250,
      result: 'success',
    );
    Mv2Analytics.logImageUpload(result: 'success', sizeBytes: 3 * 1024 * 1024);

    expect(captured[0].event, Mv2Events.replySubmit);
    expect(captured[0].params['length_bucket'], '100-499');
    expect(captured[0].params['has_quote'], true);
    expect(captured[1].event, Mv2Events.imageUpload);
    expect(captured[1].params['size_bucket'], '1mb-5mb');
  });

  test('同一交互路径的多个事件按序捕获', () {
    Mv2Analytics.logPushOpen(topicId: 42);
    Mv2Analytics.logTopicOpen(topicId: 42, source: 'push', layout: 'phone');

    expect(captured.map((c) => c.event),
        [Mv2Events.pushOpen, Mv2Events.topicOpen]);
    expect(captured[1].params['source'], 'push');
  });
}
