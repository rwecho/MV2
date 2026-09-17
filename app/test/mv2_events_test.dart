import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/telemetry/mv2_events.dart';

/// 事件目录契约:命名必须满足 Firebase Analytics 的硬限制,否则 SDK 静默
/// 丢弃事件 — 与其上线后排查「为什么没有数据」,不如在测试里拦截。
void main() {
  final nameKeyPattern = RegExp(r'^[a-z][a-z0-9_]*$');
  const reservedPrefixes = ['firebase_', 'google_', 'ga_'];

  test('每个事件名都是 snake_case 且 ≤40 字符', () {
    Mv2Events.catalog.forEach((name, params) {
      expect(name, matches(nameKeyPattern), reason: '事件名非法: $name');
      expect(name.length, lessThanOrEqualTo(40), reason: '事件名过长: $name');
    });
  });

  test('事件名不带 Firebase 保留前缀', () {
    Mv2Events.catalog.forEach((name, params) {
      for (final prefix in reservedPrefixes) {
        expect(name.startsWith(prefix), isFalse, reason: '$name 以 $prefix 开头');
      }
    });
  });

  test('每个参数键都是 snake_case 且 ≤40 字符', () {
    Mv2Events.catalog.forEach((name, params) {
      for (final key in params) {
        expect(key, matches(nameKeyPattern), reason: '$name 的参数键非法: $key');
        expect(key.length, lessThanOrEqualTo(40), reason: '$name 的参数键过长: $key');
      }
    });
  });

  test('catalog 没有重复事件名(Map 字面量本身保证,此处防重构回退)', () {
    expect(Mv2Events.catalog.length, 51);
  });

  group('lengthBucket', () {
    test('边界值落桶正确', () {
      expect(Mv2Events.lengthBucket(0), '0');
      expect(Mv2Events.lengthBucket(1), '1-19');
      expect(Mv2Events.lengthBucket(19), '1-19');
      expect(Mv2Events.lengthBucket(20), '20-99');
      expect(Mv2Events.lengthBucket(99), '20-99');
      expect(Mv2Events.lengthBucket(100), '100-499');
      expect(Mv2Events.lengthBucket(499), '100-499');
      expect(Mv2Events.lengthBucket(500), '500+');
    });
  });

  group('sizeBucket', () {
    test('边界值落桶正确', () {
      const kb = 1024;
      expect(Mv2Events.sizeBucket(0), '<100kb');
      expect(Mv2Events.sizeBucket(100 * kb - 1), '<100kb');
      expect(Mv2Events.sizeBucket(100 * kb), '100kb-1mb');
      expect(Mv2Events.sizeBucket(1024 * kb), '1mb-5mb');
      expect(Mv2Events.sizeBucket(5 * 1024 * kb), '>5mb');
    });
  });
}
