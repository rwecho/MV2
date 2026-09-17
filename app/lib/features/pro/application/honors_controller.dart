import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import '../data/honors_api.dart';
import 'pro_controller.dart';

/// 荣誉墙状态：名录 + 我是否已铭刻。
class HonorsState {
  const HonorsState({this.entries = const <HonorEntry>[], this.joined = false});

  final List<HonorEntry> entries;
  final bool joined;

  HonorsState copyWith({List<HonorEntry>? entries, bool? joined}) =>
      HonorsState(
        entries: entries ?? this.entries,
        joined: joined ?? this.joined,
      );
}

/// 本地"已铭刻"标记的持久化 key。服务端按 rcUserId 去重，这里只是让 UI
/// 不必每次打开都重复引导登记。
const String _kHonorJoinedKey = 'mv2.pro.honorJoined';

class HonorsController extends AsyncNotifier<HonorsState> {
  HonorsApi? _apiOverride;

  /// 测试注入假 API 用；生产代码不要调用。
  // coverage:ignore-start
  void debugOverrideApi(HonorsApi api) => _apiOverride = api;
  // coverage:ignore-end

  HonorsApi get _api => _apiOverride ?? HonorsApi();

  @override
  Future<HonorsState> build() async {
    var joined = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      joined = prefs.getBool(_kHonorJoinedKey) ?? false;
    } on Exception {
      // 测试环境无插件时按未登记继续。
    }
    final entries = await _api.fetch();
    return HonorsState(entries: entries, joined: joined);
  }

  /// 把 [rawName] 铭刻上墙。服务端会用 RevenueCat 核验权益，返回值直接
  /// 对应 UI 提示。
  Future<HonorJoinResult> join(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty || name.length > kMaxHonorNameLength) {
      Mv2Analytics.logHonorJoin(result: HonorJoinResult.error.name);
      return HonorJoinResult.error;
    }

    final backend = ref.read(proControllerProvider.notifier).backend;
    String rcUserId;
    try {
      rcUserId = await backend.appUserId();
    } on Exception {
      Mv2Analytics.logHonorJoin(result: HonorJoinResult.error.name);
      return HonorJoinResult.error;
    }

    final result = await _api.join(name: name, rcUserId: rcUserId);
    Mv2Analytics.logHonorJoin(result: result.name);

    if (result == HonorJoinResult.joined || result == HonorJoinResult.already) {
      await _markJoined();
    }
    if (result == HonorJoinResult.joined) {
      // 只有首次铭刻才本地追加；already 的条目刷新名单时由服务端给出。
      final current = state.value ?? const HonorsState();
      final exists = current.entries.any(
        (entry) => entry.name.toLowerCase() == name.toLowerCase(),
      );
      if (!exists) {
        state = AsyncData(
          current.copyWith(
            entries: <HonorEntry>[
              ...current.entries,
              HonorEntry(name: name, joinedAt: DateTime.now()),
            ],
          ),
        );
      }
    }
    return result;
  }

  Future<void> _markJoined() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kHonorJoinedKey, true);
    } on Exception {
      // 标记失败只影响下次引导，铭刻本身已在服务端完成。
    }
    final current = state.value ?? const HonorsState();
    state = AsyncData(current.copyWith(joined: true));
  }
}

/// 荣誉墙名字长度上限（与 Worker 端 `MAX_HONOR_NAME_LENGTH` 一致）。
const int kMaxHonorNameLength = 24;

final honorsControllerProvider =
    AsyncNotifierProvider<HonorsController, HonorsState>(HonorsController.new);
