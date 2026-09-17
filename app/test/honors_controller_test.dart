import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/features/pro/application/honors_controller.dart';
import 'package:mv2/features/pro/application/pro_backend.dart';
import 'package:mv2/features/pro/application/pro_controller.dart';
import 'package:mv2/features/pro/data/honors_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 荣誉墙登记状态机：服务端结局 → 本地标记 / 名单更新 / 遥测，各分支要闭环。
class _FakeProBackend implements ProBackend {
  const _FakeProBackend();

  @override
  bool get isConfigured => true;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<bool> checkEntitlement() async => true;

  @override
  Future<String> appUserId() async => 'rc-user-1';

  @override
  Future<ProProduct?> fetchLifetimeProduct() async => null;

  @override
  Future<ProPurchaseOutcome> purchaseLifetime() async =>
      ProPurchaseOutcome.error;

  @override
  Future<bool> restore() async => false;
}

class _FakeHonorsApi implements HonorsApi {
  _FakeHonorsApi({this.joinResult = HonorJoinResult.joined});

  HonorJoinResult joinResult;
  String? lastName;
  final List<HonorEntry> wall = <HonorEntry>[];

  @override
  Future<List<HonorEntry>> fetch() async => List.of(wall);

  @override
  Future<HonorJoinResult> join({
    required String name,
    required String rcUserId,
  }) async {
    lastName = name;
    if (joinResult == HonorJoinResult.joined) {
      wall.add(HonorEntry(name: name, joinedAt: DateTime(2026, 1, 1)));
    }
    return joinResult;
  }
}

Future<ProviderContainer> _boot({
  required _FakeHonorsApi api,
  bool persistedJoined = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (persistedJoined) 'mv2.pro.honorJoined': true,
  });
  final controller = HonorsController()..debugOverrideApi(api);
  final container = ProviderContainer(
    overrides: [
      honorsControllerProvider.overrideWith(() => controller),
      proControllerProvider.overrideWith(
        () => ProController()..debugOverrideBackend(const _FakeProBackend()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(honorsControllerProvider.future);
  return container;
}

void main() {
  test(
    'successful join records the local marker and appends the entry',
    () async {
      final api = _FakeHonorsApi();
      final container = await _boot(api: api);

      final result = await container
          .read(honorsControllerProvider.notifier)
          .join('  livid  ');

      expect(result, HonorJoinResult.joined);
      expect(api.lastName, 'livid', reason: '名字应先 trim 再上报');
      final state = container.read(honorsControllerProvider).value!;
      expect(state.joined, isTrue);
      expect(state.entries.last.name, 'livid');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('mv2.pro.honorJoined'), isTrue);
    },
  );

  test(
    're-joining keeps the joined marker without duplicating the entry',
    () async {
      final api = _FakeHonorsApi(joinResult: HonorJoinResult.already);
      final container = await _boot(api: api, persistedJoined: true);

      final result = await container
          .read(honorsControllerProvider.notifier)
          .join('livid');

      expect(result, HonorJoinResult.already);
      final state = container.read(honorsControllerProvider).value!;
      expect(state.joined, isTrue);
      expect(state.entries, isEmpty);
    },
  );

  test('name taken leaves the marker untouched', () async {
    final api = _FakeHonorsApi(joinResult: HonorJoinResult.nameTaken);
    final container = await _boot(api: api);

    final result = await container
        .read(honorsControllerProvider.notifier)
        .join('livid');

    expect(result, HonorJoinResult.nameTaken);
    expect(container.read(honorsControllerProvider).value!.joined, isFalse);
  });

  test(
    'server-side entitlement rejection is surfaced, not swallowed',
    () async {
      final api = _FakeHonorsApi(joinResult: HonorJoinResult.notEntitled);
      final container = await _boot(api: api);

      final result = await container
          .read(honorsControllerProvider.notifier)
          .join('livid');

      expect(result, HonorJoinResult.notEntitled);
      expect(container.read(honorsControllerProvider).value!.joined, isFalse);
    },
  );

  test('a persisted joined marker survives a wall reload', () async {
    final api = _FakeHonorsApi();
    final container = await _boot(api: api, persistedJoined: true);

    final state = container.read(honorsControllerProvider).value!;
    expect(state.joined, isTrue);
  });
}
