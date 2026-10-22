import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/features/pro/application/honors_controller.dart';
import 'package:mv2/features/pro/application/pro_controller.dart';
import 'package:mv2/features/pro/data/honors_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Pro extends ProController {
  @override
  Future<ProState> build() async => const ProState(entitled: true);
}

class _Api extends HonorsApi {
  HonorEntry? mine;
  HonorJoinResult result = HonorJoinResult.joined;
  bool failStatus = false;
  @override
  Future<List<HonorEntry>> fetch() async =>
      mine == null || mine!.hidden ? [] : [mine!];
  @override
  Future<HonorEntry?> status() async {
    if (failStatus) throw Exception('offline');
    return mine;
  }

  @override
  Future<HonorJoinResult> join({required String name}) async => result;
  @override
  Future<void> hide() async {}
}

Future<ProviderContainer> _boot(_Api api) async {
  // Old global marker must never override this customer's actual status.
  SharedPreferences.setMockInitialValues({'mv2.pro.honorJoined': true});
  final c = ProviderContainer(
    overrides: [
      proControllerProvider.overrideWith(_Pro.new),
      honorsControllerProvider.overrideWith(
        () => HonorsController()..debugOverrideApi(api),
      ),
    ],
  );
  addTearDown(c.dispose);
  await c.read(proControllerProvider.future);
  await c.read(honorsControllerProvider.future);
  return c;
}

void main() {
  test('server recovers the original name after reinstall', () async {
    final api = _Api()
      ..mine = HonorEntry(name: 'supporter', joinedAt: DateTime(2026));
    final c = await _boot(api);
    expect(c.read(honorsControllerProvider).value!.mine!.name, 'supporter');
  });
  test(
    'stale joined marker does not claim another customer has registered',
    () async {
      final c = await _boot(_Api());
      expect(c.read(honorsControllerProvider).value!.joined, isFalse);
    },
  );
  test(
    'status failure is explicit and does not invent a registration',
    () async {
      final c = await _boot(_Api()..failStatus = true);
      expect(c.read(honorsControllerProvider).value!.statusError, isNotNull);
      expect(c.read(isProProvider), isTrue);
    },
  );
  test('successful rename replaces old name and keeps original date', () async {
    final api = _Api()
      ..mine = HonorEntry(name: 'old', joinedAt: DateTime(2020));
    final c = await _boot(api);
    await c.read(honorsControllerProvider.notifier).join(' new ');
    final state = c.read(honorsControllerProvider).value!;
    expect(state.entries.map((e) => e.name), ['new']);
    expect(state.mine!.joinedAt, DateTime(2020));
  });
  test('name conflict preserves the original registered state', () async {
    final api = _Api()..result = HonorJoinResult.nameTaken;
    final c = await _boot(api);
    expect(
      await c.read(honorsControllerProvider.notifier).join('taken'),
      HonorJoinResult.nameTaken,
    );
    expect(c.read(honorsControllerProvider).value!.mine, isNull);
  });
  test('hiding removes public display without removing Pro', () async {
    final api = _Api()
      ..mine = HonorEntry(name: 'supporter', joinedAt: DateTime(2026));
    final c = await _boot(api);
    expect(await c.read(honorsControllerProvider.notifier).hide(), isTrue);
    expect(c.read(honorsControllerProvider).value!.mine!.hidden, isTrue);
    expect(c.read(honorsControllerProvider).value!.entries, isEmpty);
    expect(c.read(isProProvider), isTrue);
  });
}
