import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'v2ex_endpoints.dart';

/// Dart half of the `mv2/web_cookies` channel.
///
/// Google OAuth 完成后，会话 cookie（`PB3_SESSION`）是 HttpOnly 的：它只存在
/// 于应用内 WebView 背后的原生 cookie store（Android 的
/// `android.webkit.CookieManager`、iOS 的 `WKWebsiteDataStore`），页面里的
/// JavaScript 永远读不到。原生侧把 `k=v; k2=v2` 形式的 Cookie 头整个吐回来，
/// 这里解析回 [Cookie] 交给 `AuthController.signInWithCookies` 灌进 Dio 的
/// cookie jar。
class WebCookieBridge {
  const WebCookieBridge({this.channel = _defaultChannel});

  /// Keep in sync with `MainActivity.kt` and `MV2NativeBridge.swift`.
  static const MethodChannel _defaultChannel = MethodChannel('mv2/web_cookies');

  /// Injectable so tests can substitute a mock handler.
  final MethodChannel channel;

  /// Raw `Cookie` header for the v2ex.com origin, or `null` when the native
  /// side is missing (tests, unsupported platforms).
  Future<String?> cookieHeader(String url) async {
    try {
      return await channel.invokeMethod<String>(
        'getCookies',
        <String, String>{'url': url},
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Clears cookies before starting a fresh OAuth flow in the WebView, so the
  /// `once`/state 绑定到一个干净的匿名会话，且不会把上一次登录留下的旧会话
  /// 误判成「已登录」。
  ///
  /// Android 的 `android.webkit.CookieManager` 没有按域删除的 API，只能清空
  /// 整个 app 内 WebView 的 cookie jar（本 app 的 WebView 只用于登录与视频
  /// 播放，代价可忽略）；iOS 按 [url] 的 host 过滤删除。
  Future<void> clearCookies(String url) async {
    try {
      await channel.invokeMethod<void>(
        'clearCookies',
        <String, String>{'url': url},
      );
    } on MissingPluginException {
      // No native side (tests, unsupported platforms) — nothing to clear.
    } on PlatformException {
      // Best-effort: a failed clear must not block the login page.
    }
  }

  /// Parses `k=v; k2=v2` into cookies bound to the v2ex domain.
  static List<Cookie> parseHeader(String header) {
    final cookies = <Cookie>[];
    for (final pair in header.split(';')) {
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isEmpty) continue;
      cookies.add(
        Cookie(name, value)
          ..domain = V2exEndpoints.host
          ..path = '/',
      );
    }
    return cookies;
  }
}

final webCookieBridgeProvider = Provider<WebCookieBridge>(
  (ref) => const WebCookieBridge(),
);
