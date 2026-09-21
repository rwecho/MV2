import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/network/v2ex_endpoints.dart';
import '../../../core/network/web_cookie_bridge.dart';
import '../../../core/telemetry/mv2_analytics.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../auth/application/auth_controller.dart';

/// Sign in with Google —— 应用内 WebView 驱动 V2EX 的服务端 OAuth。
///
/// 流程与网页端一致：`/signin` 页上的 Google 按钮跳 `/auth/google?once=…`，
/// Google 认证完成后回跳 v2ex.com 并种下会话 cookie。cookie（`PB3_SESSION`）
/// 是 HttpOnly 的，JS 读不到，所以回到 v2ex.com 域后经 [WebCookieBridge]
/// 从原生 cookie store 收割，再交给 [AuthController.signInWithCookies] 校验
/// 并灌进 Dio 的 jar。
///
/// 为什么这里是 WebView 而登录表单不是：OAuth 必须在 v2ex.com 的浏览器会话
/// 里走完（state/cookie 校验 + Google 对嵌入式 UA 的风控），无法用原生表单
/// 复刻。桌面 Chrome UA 一是为了绕开 Google "此浏览器可能不安全" 的拦截，
/// 二是 V2EX 对 UA 无 DOM 差异（见 `V2exEndpoints.userAgent` 注释）。
class GoogleLoginPage extends ConsumerStatefulWidget {
  const GoogleLoginPage({super.key});

  @override
  ConsumerState<GoogleLoginPage> createState() => _GoogleLoginPageState();
}

class _GoogleLoginPageState extends ConsumerState<GoogleLoginPage> {
  /// Desktop Chrome on macOS —— Google 接受它发起 OAuth。
  static const String _userAgent = V2exEndpoints.desktopWriteUserAgent;

  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setUserAgent(_userAgent)
    ..setNavigationDelegate(
      NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onPageFinished: (_) => _onPageSettled(),
      ),
    )
    ..loadRequest(Uri.parse('${V2exEndpoints.baseUrl}${V2exEndpoints.signIn}'));

  int _progress = 0;

  /// `/signin` 上的 Google 按钮只自动点一次；用户取消 OAuth 回到 `/signin`
  /// 后允许再次触发（也仍然可以手动点页面里的按钮）。
  bool _authStarted = false;

  /// Cookie 收割是一次性动作：签名检查可能触发多次导航事件。
  bool _harvesting = false;

  String? _error;

  /// Runs after every page load. Two concerns, both keyed on the URL:
  /// starting the OAuth from a fresh `/signin`, and detecting the signed-in
  /// landing page the callback eventually reaches.
  Future<void> _onPageSettled() async {
    if (_harvesting) return;
    final url = Uri.tryParse(await _web.currentUrl() ?? '');
    if (url == null || url.host != V2exEndpoints.host) return;

    if (url.path == V2exEndpoints.signIn) {
      if (!_authStarted) {
        _authStarted = true;
        await _startGoogleAuth();
      }
      return;
    }

    // 回跳落点（`/` 或 OAuth 后的去向）：只有真正出现「退出登录」链接才算
    // 已登录 —— OAuth 中间页（/auth/*）也会落在 v2ex.com 域上。
    final signedIn = await _web.runJavaScriptReturningResult(
      "document.querySelector('a[href^=\"/signout\"]') ? '1' : '0'",
    );
    if ('$signedIn' == '1') {
      await _harvestCookies();
      return;
    }
    if (mounted && _authStarted && _error == null && url.path != '/auth/google') {
      // 取消或失败后 V2EX 退回 /signin；提示但不关页面，用户可以直接重试。
      setState(() => _error = 'Google 登录未完成，可在页面中重试或关闭后重来。');
    }
  }

  /// Extracts `/auth/google?once=…` from the rendered button's inline
  /// handler and follows it. Falls back to a synthetic click when V2EX
  /// changes the markup shape.
  Future<void> _startGoogleAuth() async {
    await _web.runJavaScript('''
      (function () {
        var el = document.querySelector('.sign_in_with');
        if (!el) return;
        var onclick = el.getAttribute('onclick') || '';
        var m = onclick.match(/location.href\\s*=\\s*'([^']+)'/);
        if (m) { window.location.href = m[1]; }
        else { el.click(); }
      })();
    ''');
  }

  Future<void> _harvestCookies() async {
    if (_harvesting) return;
    _harvesting = true;
    try {
      final header = await ref
          .read(webCookieBridgeProvider)
          .cookieHeader('${V2exEndpoints.baseUrl}/');
      final cookies = header == null ? null : WebCookieBridge.parseHeader(header);
      if (cookies == null || cookies.isEmpty) {
        if (!mounted) return;
        setState(() => _error = '未能读取登录会话，请重试。');
        _harvesting = false;
        return;
      }
      await ref.read(authControllerProvider.notifier).signInWithCookies(cookies);
      if (!mounted) return;
      final signedIn =
          ref.read(authControllerProvider).value?.isSignedIn ?? false;
      if (!signedIn) {
        setState(() => _error = '登录未完成，请在页面中重试。');
        _harvesting = false;
        return;
      }
      Mv2Analytics.logLoginGoogleSubmit(result: 'success');
      // 先关 OAuth 页，再关底下的登录页。
      context.pop();
      if (mounted) context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '登录失败：$error');
      _harvesting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(
        title: '使用 Google 登录',
        onBack: () {
          Mv2Analytics.logLoginGoogleSubmit(result: 'cancelled');
          context.pop();
        },
      ),
      child: Column(
        children: <Widget>[
          if (_progress < 100)
            LinearProgressIndicator(
              value: _progress / 100,
              minHeight: 2,
              backgroundColor: colors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
            ),
          if (_error != null)
            Material(
              color: colors.divider,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Mv2Spacing.pageNarrow,
                  vertical: Mv2Spacing.x2,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: colors.danger,
                    ),
                    const SizedBox(width: Mv2Spacing.x2),
                    Expanded(
                      child: Text(
                        _error!,
                        style: context.text.metadata.copyWith(
                          color: colors.danger,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _error = null),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: WebViewWidget(controller: _web)),
        ],
      ),
    );
  }
}
