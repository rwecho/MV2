import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../data/honors_api.dart';
import 'pro_controller.dart';

class HonorsState {
  const HonorsState({
    this.entries = const [],
    this.joined = false,
    this.mine,
    this.statusError,
  });
  final List<HonorEntry> entries;
  final bool joined;
  final HonorEntry? mine;
  final String? statusError;
}

class HonorsController extends AsyncNotifier<HonorsState> {
  HonorsApi? _apiOverride;
  void debugOverrideApi(HonorsApi api) => _apiOverride = api;
  HonorsApi get _api => _apiOverride ?? HonorsApi();

  @override
  Future<HonorsState> build() async {
    // Purchase/restore changes refresh the status without using a global local
    // "joined" boolean, which could belong to another store customer.
    final entitled = ref.watch(proControllerProvider).value?.entitled ?? false;
    final entries = await _api.fetch();
    if (!entitled) return HonorsState(entries: entries);
    try {
      final mine = await _api.status();
      return HonorsState(entries: entries, mine: mine, joined: mine != null);
    } on HonorProofUnavailable {
      return HonorsState(
        entries: entries,
        statusError: '此设备暂时无法提供商店购买证明，请恢复购买后重试。',
      );
    } on Exception {
      return HonorsState(
        entries: entries,
        statusError: '暂时无法查询你的署名，请稍后重试。已购买的 Pro 不受影响。',
      );
    }
  }

  Future<HonorJoinResult> join(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty || name.length > kMaxHonorNameLength) {
      return HonorJoinResult.error;
    }
    final result = await _api.join(name: name);
    Mv2Analytics.logHonorJoin(result: result.name);
    if (result == HonorJoinResult.joined || result == HonorJoinResult.already) {
      // Registration has succeeded even if the follow-up list fetch fails.
      final current = state.value ?? const HonorsState();
      final entry = HonorEntry(
        name: name,
        joinedAt: current.mine?.joinedAt ?? DateTime.now(),
      );
      state = AsyncData(
        HonorsState(
          entries: [
            ...current.entries.where(
              (e) => e.name != current.mine?.name && e.name != name,
            ),
            entry,
          ],
          mine: entry,
          joined: true,
        ),
      );
    }
    return result;
  }

  Future<bool> hide() async {
    try {
      await _api.hide();
      final current = state.value ?? const HonorsState();
      final mine = current.mine;
      state = AsyncData(
        HonorsState(
          entries: current.entries.where((e) => e.name != mine?.name).toList(),
          joined: mine != null,
          mine: mine == null
              ? null
              : HonorEntry(
                  name: mine.name,
                  joinedAt: mine.joinedAt,
                  hidden: true,
                ),
        ),
      );
      return true;
    } on Exception {
      return false;
    }
  }
}

const int kMaxHonorNameLength = 24;
final honorsControllerProvider =
    AsyncNotifierProvider<HonorsController, HonorsState>(HonorsController.new);
