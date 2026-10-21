import 'dart:async';

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
/// This WebView flow can be rejected by Google's embedded-browser policy.
/// Completion handling here only synchronizes an already-issued V2EX session;
/// it does not bypass Google authentication or certificate checks.
///
/// V2EX 的 `/signin`（桌面布局）只是取 `once` 的中间步骤，不等它渲染完成
/// 就被隐藏：WebView 加载后立即注入 JS 跳转 Google，用户看到的是加载态 →
/// Google 页面。超过 [_revealTimeout] 仍未跳转则放行显示，用户可手动点
/// 页面里的按钮。
class GoogleLoginPage extends ConsumerStatefulWidget {
  const GoogleLoginPage({super.key});

  @override
  ConsumerState<GoogleLoginPage> createState() => _GoogleLoginPageState();
}

class _GoogleLoginPageState extends ConsumerState<GoogleLoginPage> {
  /// 隐藏 V2EX 取令牌页的最长时间；超时放行（跳转失败时用户仍可手动操作）。
  static const Duration _revealTimeout = Duration(seconds: 6);

  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setUserAgent(V2exEndpoints.oauthUserAgent())
    ..setNavigationDelegate(
      NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onPageFinished: (_) => _onPageSettled(),
      ),
    );

  int _progress = 0;

  /// `/signin` 上的 Google 按钮只自动点一次；用户取消 OAuth 回到 `/signin`
  /// 后允许再次触发（也仍然可以手动点页面里的按钮）。
  bool _authStarted = false;

  /// Cookie 收割是一次性动作：签名检查可能触发多次导航事件。
  bool _harvesting = false;
  bool _completed = false;

  /// V2EX 取令牌页是否已放行显示。
  bool _revealed = false;
  Timer? _revealTimer;

  String? _error;

  bool get _active => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _revealTimer = Timer(_revealTimeout, _reveal);
    _prepareAndLoad();
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  /// 残留 cookie 必须在第一次页面加载前清掉，否则 V2EX 可能直接 302 走
  /// `/signin`（旧会话还在），OAuth 的 `once` 就绑不到干净会话上。
  Future<void> _prepareAndLoad() async {
    await ref
        .read(webCookieBridgeProvider)
        .clearCookies('${V2exEndpoints.baseUrl}/');
    if (!mounted) return;
    await _web.loadRequest(
      Uri.parse('${V2exEndpoints.baseUrl}${V2exEndpoints.signIn}'),
    );
  }

  void _reveal() {
    _revealTimer?.cancel();
    if (!mounted || _revealed) return;
    setState(() => _revealed = true);
  }

  /// Runs after every page load. Three concerns, all keyed on the URL:
  /// revealing the page once we leave the token-grab `/signin`, starting the
  /// OAuth from that page, and detecting the signed-in landing page the
  /// callback eventually reaches.
  Future<void> _onPageSettled() async {
    if (!_active || _harvesting || _completed) return;
    final url = Uri.tryParse(await _web.currentUrl() ?? '');
    if (!_active || url == null) return;

    final onV2exSignin = _isV2ex(url) && url.path == V2exEndpoints.signIn;
    if (!onV2exSignin) _reveal();

    if (!_isV2ex(url)) return;

    if (url.path == V2exEndpoints.signIn && !_authStarted) {
      _authStarted = true;
      await _startGoogleAuth();
      return;
    }

    // A mobile menu may never mount a /signout anchor. JS string results also
    // differ between WKWebView and Android. Neither is an authentication check:
    // copy the native cookies and let currentUser validate the session.
    if (_authStarted && !url.path.startsWith('/auth/')) {
      await _harvestCookies();
    }
  }

  bool _isV2ex(Uri url) =>
      url.scheme == 'https' &&
      (url.host == V2exEndpoints.host || url.host == 'v2ex.com');

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
    if (_harvesting || _completed || !_active) return;
    _harvesting = true;
    setState(() => _error = null);
    try {
      // OAuth 回跳后，会话 cookie 写入 WKHTTPCookieStore 比页面渲染慢一拍：
      // DOM 已是已登录、cookie store 里可能还是旧值（xinghelee/v2ex 记录过
      // 同样现象：「Cookie 写入稍有延迟时会短暂重试」）。所以第一次拿不到
      // 有效会话不报错，短暂重试，耗尽才提示。
      for (var attempt = 1; attempt <= 3; attempt++) {
        if (!_active) return;
        final current = Uri.tryParse(await _web.currentUrl() ?? '');
        if (!_active ||
            current == null ||
            !_isV2ex(current) ||
            current.path.startsWith('/auth/')) {
          return;
        }
        final header = await ref
            .read(webCookieBridgeProvider)
            .cookieHeader('${V2exEndpoints.baseUrl}/');
        final cookies = header == null
            ? null
            : WebCookieBridge.parseHeader(header);
        if (mounted) {
          debugPrint(
            'MV2 Google: harvest attempt $attempt, '
            'cookies=${cookies?.length ?? 0}',
          );
        }
        if (cookies == null || cookies.isEmpty) {
          if (attempt < 3) {
            await Future<void>.delayed(const Duration(milliseconds: 800));
            continue;
          }
          if (!_active) return;
          setState(() => _error = '未能读取登录会话，请重试。');
          _harvesting = false;
          return;
        }
        if (!_active) return;
        await ref
            .read(authControllerProvider.notifier)
            .signInWithCookies(cookies);
        if (!mounted || !_active) return;
        final signedIn =
            ref.read(authControllerProvider).value?.isSignedIn ?? false;
        if (signedIn) {
          Mv2Analytics.logLoginGoogleSubmit(result: 'success');
          _completed = true;
          // The caller owns dismissing /login. Never pop the topic underneath.
          if (context.canPop()) {
            context.pop(true);
          } else {
            context.go('/feed');
          }
          return;
        }
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          continue;
        }
        setState(() => _error = '尚未同步登录状态，请点击重新同步；若网页尚未登录，请先完成登录。');
        _harvesting = false;
      }
    } catch (error) {
      if (!_active) return;
      setState(() => _error = '登录失败：$error');
      _harvesting = false;
    } finally {
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
                    TextButton(
                      onPressed: _harvesting ? null : _onPageSettled,
                      child: const Text('重新同步'),
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
          Expanded(
            // IndexedStack 而不是条件渲染：WebView 必须保持挂载，取令牌页
            // 上的 JS 跳转才不会被打断。
            child: IndexedStack(
              index: _revealed ? 0 : 1,
              children: <Widget>[
                WebViewWidget(controller: _web),
                if (_revealed)
                  const SizedBox.shrink()
                else
                  Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
