import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/telemetry/mv2_analytics.dart';
import 'pro_backend.dart';
import 'revenuecat_pro_backend.dart';

/// 付费墙与全应用的永久权益状态。
class ProState {
  const ProState({
    this.configured = false,
    this.entitled = false,
    this.product,
  });

  /// 后端是否具备可购配置（公钥注入、平台受支持）。
  final bool configured;

  /// 是否已解锁永久版。
  final bool entitled;

  /// 商店里的终身买断商品；null = 还没拉到 / 商店无商品。
  final ProProduct? product;

  ProState copyWith({bool? configured, bool? entitled, ProProduct? product}) =>
      ProState(
        configured: configured ?? this.configured,
        entitled: entitled ?? this.entitled,
        product: product ?? this.product,
      );
}

/// 权益的本地持久化 key。权益是"最后一次已知状态"，真值永远在 RevenueCat；
/// 启动先读缓存让 UI 立即可用，再用 SDK 异步校正。
const String _kEntitledKey = 'mv2.pro.entitled';

class ProController extends AsyncNotifier<ProState> {
  ProBackend? _backendOverride;

  /// 测试注入假后端用；生产代码不要调用。
  // coverage:ignore-start
  void debugOverrideBackend(ProBackend backend) => _backendOverride = backend;
  // coverage:ignore-end

  ProBackend get backend => _backendOverride ?? RevenueCatProBackend();

  @override
  Future<ProState> build() async {
    // 先用本地缓存回答"是否已解锁"，UI 无需等网络。
    var entitled = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      entitled = prefs.getBool(_kEntitledKey) ?? false;
    } on Exception {
      // 测试环境可能没有插件；按未解锁继续。
    }

    final backend = this.backend;
    if (!backend.isConfigured) {
      return ProState(configured: false, entitled: entitled);
    }

    try {
      await backend.ensureReady();
      entitled = await backend.checkEntitlement();
      final product = await backend.fetchLifetimeProduct();
      await _persist(entitled);
      return ProState(configured: true, entitled: entitled, product: product);
    } on ProUnconfiguredException {
      return ProState(configured: false, entitled: entitled);
    } on Exception {
      // 拉取失败不阻塞界面：保留缓存权益，付费墙里可重试。
      return ProState(configured: true, entitled: entitled);
    }
  }

  /// 发起终身买断购买，返回结局并同步权益/遥测。
  Future<ProPurchaseOutcome> purchase() async {
    final backend = this.backend;
    if (!backend.isConfigured) {
      Mv2Analytics.logPurchaseResult(result: 'unconfigured');
      return ProPurchaseOutcome.error;
    }
    try {
      await backend.ensureReady();
    } on ProUnconfiguredException {
      Mv2Analytics.logPurchaseResult(result: 'unconfigured');
      return ProPurchaseOutcome.error;
    }

    final outcome = await backend.purchaseLifetime();
    Mv2Analytics.logPurchaseResult(result: outcome.name);
    if (outcome == ProPurchaseOutcome.success) {
      await _setEntitled(true);
    } else if (outcome == ProPurchaseOutcome.pending) {
      // 权益稍后由商店批准生效；下次启动 checkEntitlement 会校正。
    }
    return outcome;
  }

  /// 恢复购买（换机/重装后找回永久权益）。
  Future<bool> restore() async {
    final backend = this.backend;
    if (!backend.isConfigured) {
      Mv2Analytics.logRestoreResult(result: 'error');
      return false;
    }
    try {
      await backend.ensureReady();
    } on ProUnconfiguredException {
      Mv2Analytics.logRestoreResult(result: 'error');
      return false;
    }

    try {
      final entitled = await backend.restore();
      await _setEntitled(entitled);
      Mv2Analytics.logRestoreResult(
        result: entitled ? 'success' : 'no_entitlement',
      );
      return entitled;
    } on Exception {
      Mv2Analytics.logRestoreResult(result: 'error');
      return false;
    }
  }

  Future<void> _setEntitled(bool entitled) async {
    await _persist(entitled);
    final current = state.value ?? const ProState();
    state = AsyncData(current.copyWith(entitled: entitled));
  }

  Future<void> _persist(bool entitled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEntitledKey, entitled);
    } on Exception {
      // 持久化失败只影响下次冷启动的速度，不影响本次会话。
    }
  }
}

final proControllerProvider = AsyncNotifierProvider<ProController, ProState>(
  ProController.new,
);

/// 全应用门控读取点：`ref.watch(isProProvider)` 即"是否已解锁永久版"。
/// 骨架阶段没有任何功能依赖它，后续门控一行接入。
final isProProvider = Provider<bool>(
  (ref) => ref.watch(proControllerProvider).value?.entitled ?? false,
);
