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
