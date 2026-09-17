/// 永久买断的后端抽象。
///
/// [ProController] 只依赖这个接口,Widget 测试用假实现驱动;生产实现是
/// `RevenueCatProBackend`(purchases_flutter → App Store / Google Play)。
library;

/// 商店里可买的终身买断商品(已按当前 storefront 定价)。
class ProProduct {
  const ProProduct({required this.title, required this.price});

  /// 商店本地化的商品名(如 `MV2 永久版`)。
  final String title;

  /// 已格式化的本地价格(如 `¥68.00` / `$8.99`)。
  final String price;
}

/// 一次购买动作的结局。
enum ProPurchaseOutcome {
  /// 拿到权益。
  success,

  /// 用户在商店弹窗里取消。
  cancelled,

  /// 商店返回"等待中"(家庭共享审批/线下支付等),权益稍后生效。
  pending,

  /// 其它失败(网络/商品缺失/设备不支持)。
  error,
}

/// 权益标识。RevenueCat 后台创建同名 entitlement,两商店的商品都挂到它上面。
const String kProEntitlementId = 'pro';

/// 永久买断的商品标识(App Store Connect 非消耗型 + Play 应用内商品同名)。
const String kProLifetimeProductId = 'mv2.pro.lifetime';

/// 后端未配置(缺 RevenueCat 公钥)时抛出,由 controller 转成不可购状态。
class ProUnconfiguredException implements Exception {
  const ProUnconfiguredException();

  @override
  String toString() => 'Pro backend is not configured';
}

abstract interface class ProBackend {
  /// 是否具备可用配置(公钥注入、平台受支持)。false 时付费墙不可购。
  bool get isConfigured;

  /// 确保 SDK 已初始化(幂等);未配置抛 [ProUnconfiguredException]。
  Future<void> ensureReady();

  /// 当前是否已拥有永久权益(SDK 本地缓存,可离线)。
  Future<bool> checkEntitlement();

  /// RevenueCat 的 app user id —— 荣誉墙登记用它标识"这一份买断"。
  Future<String> appUserId();

  /// 拉取终身买断商品;商店未配置商品/无网时返回 null。
  Future<ProProduct?> fetchLifetimeProduct();

  /// 发起购买并返回结局;成功时权益已经生效。
  Future<ProPurchaseOutcome> purchaseLifetime();

  /// 恢复购买;返回恢复后是否拥有权益。
  Future<bool> restore();
}
