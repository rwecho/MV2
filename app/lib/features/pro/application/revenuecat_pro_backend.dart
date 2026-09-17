import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import 'pro_backend.dart';

/// RevenueCat 生产实现。
///
/// 公钥是客户端公开凭据，通过 `--dart-define` 注入（CI/构建时传入，仓库不落盘）：
///
/// ```sh
/// flutter run \
///   --dart-define=MV2_REVENUECAT_APPLE_KEY=appl_xxx \
///   --dart-define=MV2_REVENUECAT_GOOGLE_KEY=goog_xxx
/// ```
///
/// RevenueCat 后台需要：App（iOS + Android 各一把公钥）、entitlement `pro`、
/// 挂在 entitlement 上的终身包（`$rc_lifetime`，商品 id
/// [kProLifetimeProductId]）。缺公钥时 [isConfigured] 为 false，付费墙进入
/// 不可购状态而不是在运行时崩掉 —— 本地开发与 CI 不配 key 也能跑。
class RevenueCatProBackend implements ProBackend {
  RevenueCatProBackend({
    this.appleKey = const String.fromEnvironment('MV2_REVENUECAT_APPLE_KEY'),
    this.googleKey = const String.fromEnvironment('MV2_REVENUECAT_GOOGLE_KEY'),
    this.entitlementId = kProEntitlementId,
  });

  final String appleKey;
  final String googleKey;
  final String entitlementId;

  bool _configured = false;

  /// 当前平台对应的公钥（公钥本身是公开凭据，不涉密）。
  String get _apiKey {
    if (kIsWeb) return '';
    try {
      if (Platform.isIOS || Platform.isMacOS) return appleKey;
      if (Platform.isAndroid) return googleKey;
    } on UnsupportedError {
      // 非 web 平台探测失败（测试环境）按未配置处理。
      return '';
    }
    return '';
  }

  @override
  bool get isConfigured => _apiKey.isNotEmpty;

  @override
  Future<void> ensureReady() async {
    if (_configured) return;
    if (!isConfigured) throw const ProUnconfiguredException();
    await Purchases.setLogLevel(LogLevel.warn);
    await Purchases.configure(PurchasesConfiguration(_apiKey));
    _configured = true;
  }

  @override
  Future<bool> checkEntitlement() async {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.all[entitlementId]?.isActive ?? false;
  }

  @override
  Future<String> appUserId() => Purchases.appUserID;

  @override
  Future<ProProduct?> fetchLifetimeProduct() async {
    final offerings = await Purchases.getOfferings();
    final package = offerings.current?.lifetime;
    if (package == null) return null;
    return ProProduct(
      title: package.storeProduct.title,
      price: package.storeProduct.priceString,
    );
  }

  @override
  Future<ProPurchaseOutcome> purchaseLifetime() async {
    final offerings = await Purchases.getOfferings();
    final package = offerings.current?.lifetime;
    if (package == null) return ProPurchaseOutcome.error;
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return _entitled(result.customerInfo)
          ? ProPurchaseOutcome.success
          : ProPurchaseOutcome.error;
    } on PlatformException catch (e) {
      return _outcomeOf(e);
    }
  }

  @override
  Future<bool> restore() async {
    final info = await Purchases.restorePurchases();
    return _entitled(info);
  }

  bool _entitled(CustomerInfo info) =>
      info.entitlements.all[entitlementId]?.isActive ?? false;

  ProPurchaseOutcome _outcomeOf(PlatformException e) {
    switch (PurchasesErrorHelper.getErrorCode(e)) {
      case PurchasesErrorCode.purchaseCancelledError:
        return ProPurchaseOutcome.cancelled;
      case PurchasesErrorCode.paymentPendingError:
        return ProPurchaseOutcome.pending;
      default:
        return ProPurchaseOutcome.error;
    }
  }
}
