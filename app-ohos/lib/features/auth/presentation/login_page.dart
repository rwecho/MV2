import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../design_system/theme/mv2_theme.dart';
import '../../../design_system/tokens/mv2_radius.dart';
import '../../../design_system/tokens/mv2_spacing.dart';
import '../../../shared/models/login_form.dart';
import '../../../ui/components/mv2_page_header.dart';
import '../../../ui/components/mv2_page_scaffold.dart';
import '../../../ui/components/states/mv2_state_view.dart';
import '../../auth/application/auth_controller.dart';

/// Native V2EX sign-in.
///
/// The site randomises the credential field names on every render, so the form
/// is scraped first ([V2exApi.loginForm]) and this page renders its own
/// MV2-styled fields before posting those exact names back.
///
/// A WebView was tried first and rejected: V2EX serves a desktop layout inside a
/// phone-sized WebView, which cannot match the MV2 design system.
///
/// No mockup exists for this screen; it follows the Reply Composer's visual
/// language (`docs/06` → 额外必备页面 / Login).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _captcha = TextEditingController();
  final TextEditingController _twoFactorCode = TextEditingController();

  V2LoginForm? _form;
  Uint8List? _captchaImage;
  List<String> _errors = const <String>[];
  bool _loadingForm = true;
  bool _loadingCaptcha = false;
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _needsTwoFactor = false;
  bool _formUnavailable = false;

  /// Why the form could not be scraped, when known — used to pick the title.
  Failure? _formFailure;

  @override
  void initState() {
    super.initState();
    _loadForm();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _captcha.dispose();
    _twoFactorCode.dispose();
    super.dispose();
  }

  /// Scrapes a fresh `/signin` render and loads the captcha that belongs to it.
  ///
  /// [keepErrors] lets a failed submit re-scrape without dropping the message
  /// V2EX returned for it (the page must keep the reason visible while the
  /// token underneath is refreshed).
  Future<void> _loadForm({List<String> keepErrors = const <String>[]}) async {
    setState(() {
      _loadingForm = true;
      _formUnavailable = false;
      _errors = keepErrors;
      _formFailure = null;
    });
    try {
      final form = await ref.read(v2exApiProvider).loginForm();
      if (!mounted) return;
      if (form == null) {
        // Either the session is already valid (V2EX redirects away from
        // `/signin`) or the login surface is restricted.
        await ref.read(authControllerProvider.notifier).refreshAccount();
        if (!mounted) return;
        if (ref.read(authControllerProvider).value?.isSignedIn ?? false) {
          context.pop();
          return;
        }
        setState(() {
          _loadingForm = false;
          _formUnavailable = true;
          // Fixture mode has no login endpoint at all, so say so instead of
          // blaming the network.
          _errors = <String>[
            kUseFixtureApi
                ? '离线样本模式没有登录接口。请用 '
                      '--dart-define=MV2_FIXTURES=false 连接 V2EX 后再登录。'
                : 'V2EX 没有返回可用的登录表单（页面结构可能已变更），请稍后重试。',
          ];
        });
        return;
      }
      setState(() {
        _form = form;
        _loadingForm = false;
        _formFailure = null;
      });
      await _refreshCaptcha();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingForm = false;
        _formUnavailable = true;
        _formFailure = error is Failure ? error : null;
        _errors = <String>[_describe(error)];
      });
    }
  }

  /// Fetches a fresh captcha image for the **current** [V2LoginForm].
  ///
  /// The captcha endpoint is bound to the session, not to `once`: verified
  /// against the live site, `GET /_captcha?once={stale}` still answers
  /// `200 image/png`, so the manual refresh tap does not need a re-scrape. A
  /// failed submit does, because it changes `once` (see [_submit]).
  Future<void> _refreshCaptcha() async {
    final form = _form;
    if (form == null || _loadingCaptcha) return;
    setState(() => _loadingCaptcha = true);
    try {
      final bytes = await ref
          .read(v2exApiProvider)
          .captchaImage(form.captchaPath, once: form.once);
      if (!mounted) return;
      setState(() {
        _captchaImage = Uint8List.fromList(bytes);
        _loadingCaptcha = false;
        _captcha.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCaptcha = false;
        _captchaImage = null;
      });
    }
  }

  Future<void> _submit() async {
    final form = _form;
    if (form == null || _submitting) return;

    if (_needsTwoFactor) {
      await _submitTwoFactor(form);
      return;
    }

    final username = _username.text.trim();
    final password = _password.text;
    final captcha = _captcha.text.trim();
    if (username.isEmpty || password.isEmpty || captcha.isEmpty) {
      setState(() => _errors = <String>['请填写用户名、密码与验证码。']);
      return;
    }

    setState(() {
      _submitting = true;
      _errors = const <String>[];
    });

    try {
      final result = await ref
          .read(v2exApiProvider)
          .login(
            form: form,
            username: username,
            password: password,
            captcha: captcha,
          );
      if (!mounted) return;

      if (result.success) {
        await _finishSignIn();
        return;
      }
      if (result.twoFactor) {
        setState(() {
          _needsTwoFactor = true;
          _submitting = false;
          _errors = <String>['该账号开启了两步验证，请输入动态验证码。'];
        });
        return;
      }

      // V2EX re-renders the whole `/signin` form on a failed POST and issues a
      // fresh `once` with it (verified live: a wrong-captcha POST answers 200
      // with a new `once`). Resubmitting the old token is rejected with
      // `CSRF 失效，请重新提交`, so the form — not just the captcha image — must
      // be re-scraped before the user can try again. `_loadForm` also reloads
      // the captcha that goes with the new render.
      final messages = _describeLoginErrors(result.errors);
      setState(() {
        _submitting = false;
        _errors = messages;
      });
      await _loadForm(keepErrors: messages);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errors = <String>[_describe(error)];
      });
    }
  }

  Future<void> _submitTwoFactor(V2LoginForm form) async {
    final code = _twoFactorCode.text.trim();
    if (code.isEmpty) {
      setState(() => _errors = <String>['请输入两步验证码。']);
      return;
    }
    setState(() {
      _submitting = true;
      _errors = const <String>[];
    });
    try {
      final result = await ref
          .read(v2exApiProvider)
          .twoStep(form: form, code: code);
      if (!mounted) return;
      if (result.success) {
        await _finishSignIn();
        return;
      }
      setState(() {
        _submitting = false;
        _errors = result.errors.isEmpty ? <String>['验证码不正确。'] : result.errors;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errors = <String>[_describe(error)];
      });
    }
  }

  /// Cookies are already in the Dio jar (the CookieManager interceptor stored
  /// the `Set-Cookie` from the POST); this validates them and loads the profile.
  Future<void> _finishSignIn() async {
    await ref.read(authControllerProvider.notifier).refreshAccount();
    if (!mounted) return;
    final signedIn =
        ref.read(authControllerProvider).value?.isSignedIn ?? false;
    if (!signedIn) {
      setState(() {
        _submitting = false;
        _errors = <String>['登录未完成，请重试。'];
      });
      await _loadForm();
      return;
    }
    // No SnackBar here: showing one in the same frame as the pop collides with
    // the outgoing route's SnackBar Hero tag, and the profile page already
    // reflects the new state.
    context.pop();
  }

  /// A concrete failure outranks the fixture-mode hint: if V2EX actually told
  /// us something (rate limit, network), that is what the user needs to see.
  String get _formTitle {
    if (_formFailure is RateLimitFailure) return '登录尝试过于频繁';
    if (kUseFixtureApi) return '离线样本模式无法登录';
    return _formTitleForFailure(_formFailure);
  }

  @override
  Widget build(BuildContext context) {
    return Mv2PageScaffold(
      header: Mv2SecondaryHeader(title: '登录 V2EX', onBack: () => context.pop()),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingForm) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_formUnavailable || _form == null) {
      return Mv2StateView(
        kind: Mv2StateKind.error,
        title: _formTitle,
        description: _errors.isEmpty ? '请检查网络后重试。' : _errors.first,
        // A rate limit is not a transport hiccup: retrying immediately is what
        // got us here, so offer the browser instead of a retry button.
        actionLabel: _formFailure is RateLimitFailure ? '用浏览器打开' : '重试',
        onAction: _formFailure is RateLimitFailure
            ? () => launchUrl(
                Uri.parse('https://www.v2ex.com/signin'),
                mode: LaunchMode.externalApplication,
              )
            : _loadForm,
      );
    }

    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x4,
        Mv2Spacing.pageNarrow,
        Mv2Spacing.x8,
      ),
      children: <Widget>[
        Text(
          '登录 V2EX',
          style: context.text.topicTitleLarge.copyWith(
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: Mv2Spacing.x2),
        Text(
          'MV2 不会保存你的密码，验证码由 V2EX 官方提供。',
          style: context.text.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Mv2Spacing.x5),

        if (_needsTwoFactor)
          _twoFactorFields(context)
        else
          _credentialFields(context),

        if (_errors.isNotEmpty) ...<Widget>[
          const SizedBox(height: Mv2Spacing.x3),
          for (final error in _errors)
            Padding(
              padding: const EdgeInsets.only(bottom: Mv2Spacing.x1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: colors.danger,
                  ),
                  const SizedBox(width: Mv2Spacing.x2),
                  Expanded(
                    child: Text(
                      error,
                      style: context.text.metadata.copyWith(
                        color: colors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],

        const SizedBox(height: Mv2Spacing.x5),
        _submitButton(context),
      ],
    );
  }

  Widget _credentialFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _username,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(hintText: '用户名或电子邮件地址'),
          style: context.text.body.copyWith(color: context.colors.textPrimary),
        ),
        const SizedBox(height: Mv2Spacing.x3),
        TextField(
          controller: _password,
          obscureText: _obscurePassword,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: '密码',
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          style: context.text.body.copyWith(color: context.colors.textPrimary),
        ),
        const SizedBox(height: Mv2Spacing.x3),
        TextField(
          controller: _captcha,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(hintText: '验证码'),
          style: context.text.body.copyWith(color: context.colors.textPrimary),
        ),
        const SizedBox(height: Mv2Spacing.x3),
        // V2EX renders a 320x80 (4:1) captcha; give it the full width so the
        // characters stay readable and tapping it refreshes.
        AspectRatio(aspectRatio: 4, child: _captchaBox(context)),
        const SizedBox(height: Mv2Spacing.x2),
        Text(
          '看不清？点图片换一张',
          style: context.text.metadata.copyWith(
            color: context.colors.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _twoFactorFields(BuildContext context) {
    return TextField(
      controller: _twoFactorCode,
      keyboardType: TextInputType.number,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(hintText: '两步验证码'),
      style: context.text.body.copyWith(color: context.colors.textPrimary),
    );
  }

  Widget _captchaBox(BuildContext context) {
    final colors = context.colors;
    final image = _captchaImage;

    return GestureDetector(
      onTap: _loadingCaptcha ? null : _refreshCaptcha,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.divider,
          borderRadius: Mv2Radius.allSm,
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: image == null
            ? (_loadingCaptcha
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.accent,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: colors.textTertiary,
                    ))
            : Image.memory(image, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }

  Widget _submitButton(BuildContext context) {
    final colors = context.colors;
    final enabled = !_submitting;

    return SizedBox(
      height: 48,
      child: Material(
        color: enabled ? colors.accent : colors.divider,
        borderRadius: Mv2Radius.allSm,
        child: InkWell(
          borderRadius: Mv2Radius.allSm,
          onTap: enabled ? _submit : null,
          child: Center(
            child: _submitting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colors.accentContrast,
                      ),
                    ),
                  )
                : Text(
                    _needsTwoFactor ? '提交验证码' : '登录',
                    style: context.text.button.copyWith(
                      color: colors.accentContrast,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Turns a thrown error into a message a user can act on.
///
/// Without this the page only showed the generic title, which made a network
/// or proxy problem look like a broken form.
String _describe(Object error) {
  if (error is Failure) return error.message;
  return '$error';
}

/// Normalises the messages V2EX returned for a failed login submit.
///
/// The raw `CSRF 失效，请重新提交` names an internal token the user cannot see;
/// it is surfaced as an actionable instruction instead of being swallowed. Any
/// other message (captcha, credentials, anti-flood) is passed through verbatim.
List<String> _describeLoginErrors(List<String> errors) {
  if (errors.isEmpty) {
    return const <String>['登录失败，请检查账号、密码与验证码。'];
  }
  return errors
      .map((error) => error.contains('CSRF') ? '登录令牌已过期，请重试' : error)
      .toList(growable: false);
}

/// Names the real reason in the title; the generic wording made a rate limit
/// look like a broken page.
String _formTitleForFailure(Failure? failure) {
  if (failure is RateLimitFailure) return '登录尝试过于频繁';
  if (failure is NetworkFailure) return '网络连接失败';
  return '无法加载登录表单';
}
