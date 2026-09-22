import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/telemetry/mv2_analytics.dart';

/// 「我的」页推广动作 — 给个好评 / 兑换码 / 分享给朋友。
///
/// 商店身份沿用既有上架信息（App Store 数字 id 是 iTunes Lookup 按
/// bundleId 查到的在架 id，写死在这里；包名与 Android 一致）。改动任何
/// 一个都等于指向另一个应用，不要随手动。
///
/// 桌面/Web/鸿蒙没有商店，入口降级：给个好评与兑换码只在 [onStorePlatform]
/// 显示（见 profile_page），所有动作兜底都能落到 GitHub 仓库。
abstract final class AppPromotion {
  static const String appleAppId = '6757801437';
  static const String packageName = 'tech.zb.v2ex.maui.app';
  static const String githubUrl = 'https://github.com/rwecho/V2ex.Maui2';

  /// 是否装在有应用商店的平台（iOS / Android）。
  static bool get onStorePlatform => _isIos || _isAndroid;

  /// 给个好评。
  ///
  /// iOS 由用户主动点击，按 HIG 直达商店「写评价」页（系统评分弹窗留给
  /// 场景化时机，且不保证每次弹出，不适合做按钮反馈）；Android 用 Play
  /// 系统内评分弹窗，不可用（未装 Play / 系统限流）时退商店详情页。
  static Future<void> requestReview(BuildContext context) async {
    if (_isIos) {
      Mv2Analytics.logAppReview(method: 'write_review_page');
      await _open(
        context,
        Uri.parse('https://apps.apple.com/app/id$appleAppId?action=write-review'),
      );
      return;
    }
    if (_isAndroid) {
      try {
        if (await InAppReview.instance.isAvailable()) {
          Mv2Analytics.logAppReview(method: 'native_dialog');
          await InAppReview.instance.requestReview();
          return;
        }
      } catch (error) {
        // 评分弹窗拿不到不阻断入口：退到商店详情页。
        debugPrint('MV2: in-app review unavailable: $error');
      }
      Mv2Analytics.logAppReview(method: 'store_page');
      if (!context.mounted) return;
      await _open(context, Uri.parse(_playStoreUrl));
      return;
    }
    Mv2Analytics.logAppReview(method: 'github');
    await _open(context, Uri.parse(githubUrl));
  }

  /// 兑换码：交给系统商店自己的兑换界面输入，应用内不做输入框。
  ///
  /// App Store 兑换面板在 iOS 16 起没有公开 API，官方推荐通用链接；
  /// Play 用 redeem 深链。
  static Future<void> openRedeem(BuildContext context) async {
    Mv2Analytics.logAppRedeem();
    await _open(
      context,
      Uri.parse(
        _isIos
            ? 'https://apps.apple.com/redeem?ctx=offershare'
            : (_isAndroid ? _playRedeemUrl : githubUrl),
      ),
    );
  }

  /// 分享给朋友：带上当前平台的商店链接（无商店平台带 GitHub）。
  static Future<void> shareApp(BuildContext context) async {
    Mv2Analytics.logAppShare();
    final storeUrl = _isIos
        ? 'https://apps.apple.com/app/id$appleAppId'
        : (_isAndroid ? _playStoreUrl : githubUrl);
    final text = '我在用 MV2 —— 更好的 V2EX 客户端\n$storeUrl';
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = (box != null && box.hasSize)
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: origin),
      );
    } catch (error, stackTrace) {
      debugPrint('MV2: share app failed: $error\n$stackTrace');
      try {
        await Clipboard.setData(ClipboardData(text: storeUrl));
      } catch (_) {}
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开分享面板，链接已复制到剪贴板')),
      );
    }
  }

  // --------------------------------------------------------------- helpers

  static String get _playStoreUrl =>
      'https://play.google.com/store/apps/details?id=$packageName';
  static String get _playRedeemUrl => 'https://play.google.com/redeem';

  static bool get _isIos => _platform(() => Platform.isIOS);
  static bool get _isAndroid => _platform(() => Platform.isAndroid);

  /// 只有非 web 平台才允许摸 dart:io；探测失败（web/测试环境）按无商店处理。
  static bool _platform(bool Function() probe) {
    if (kIsWeb) return false;
    try {
      return probe();
    } on UnsupportedError {
      return false;
    }
  }

  /// 打开外部链接（系统浏览器/商店，不进应用内 webview），失败时把链接
  /// 拷到剪贴板兜底。messenger 在进异步前取好，避免拿着 context 跨间隙。
  static Future<void> _open(BuildContext context, Uri url) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('MV2: open $url failed: $error');
    }
    if (opened) return;
    try {
      await Clipboard.setData(ClipboardData(text: url.toString()));
    } catch (_) {}
    messenger.showSnackBar(
      const SnackBar(content: Text('无法打开应用商店，链接已复制到剪贴板')),
    );
  }
}
