import '../../shared/models/login_form.dart';
import 'html_dom.dart';

/// Scrapes `/signin` so a native form can be submitted.
///
/// Verified against the live page (2026-09-11):
///
/// ```html
/// <form method="post" action="/signin">
///   <input type="text"     class="sl" name="03945380…" placeholder="用户名或电子邮件地址">
///   <input type="password" class="sl" name="a0dd3ece…">
///   <img id="captcha-image" src="/_captcha" alt="CAPTCHA" onclick="refreshCaptcha()">
///   <input type="text"     class="sl" name="41e61f8c…" placeholder="请输入上图中的验证码…">
///   <input type="hidden" value="84014" name="once">
///   <input type="submit" class="super normal button" value="登录">
///   <input type="hidden" value="/" name="next">
/// </form>
/// ```
///
/// The credential inputs carry **randomised hex names**, so they are located by
/// position + type (first text input = username, the last text input = captcha).
abstract final class LoginFormParser {
  static V2LoginForm? parse(String html) {
    final document = parseHtmlDocument(html);
    final form =
        document.querySelector('form[action="/signin"]') ??
        document.querySelector('form');
    if (form == null) return null;

    final textInputs = form
        .querySelectorAll('input[type="text"]')
        .where((input) => (input.attributes['name'] ?? '').isNotEmpty)
        .toList(growable: false);
    final passwordInput = form.querySelector('input[type="password"][name]');

    final once = form.attrOf('input[name="once"]', 'value');
    if (textInputs.length < 2 || passwordInput == null || once == null) {
      // Either a restricted/locked variant or the markup changed.
      return null;
    }

    final captchaImage =
        form.querySelector('img#captcha-image') ??
        form.querySelector('img[alt="CAPTCHA"]');

    return V2LoginForm(
      usernameFieldName: textInputs.first.attributes['name']!,
      passwordFieldName: passwordInput.attributes['name']!,
      captchaFieldName: textInputs.last.attributes['name']!,
      once: once,
      next: form.attrOf('input[name="next"]', 'value') ?? '/',
      captchaPath:
          absoluteV2exUrl(captchaImage?.attributes['src']) ??
          'https://www.v2ex.com/_captcha',
    );
  }

  /// Read the challenge's own hidden fields and POST target. Never reuse the
  /// password form's once token or guess the verification input's name.
  static V2TwoFactorForm? parseTwoFactor(String html, {required String path}) {
    final document = parseHtmlDocument(html);
    final page = Uri.parse('https://www.v2ex.com').resolve(path);
    for (final form in document.querySelectorAll('form')) {
      final target = page.resolve(form.attributes['action'] ?? '');
      if (target.origin != page.origin || target.path != '/2fa') continue;
      final inputs = form.querySelectorAll('input[name]');
      final candidates = inputs.where((input) {
        final type = (input.attributes['type'] ?? 'text').toLowerCase();
        return const ['text', 'number', 'tel', 'password'].contains(type);
      }).toList();
      if (candidates.length != 1) continue;
      final fields = <String, String>{
        for (final input in inputs)
          if (input.attributes['type']?.toLowerCase() == 'hidden')
            input.attributes['name']!: input.attributes['value'] ?? '',
      };
      return V2TwoFactorForm(
        path: target.replace(fragment: '').toString(),
        codeFieldName: candidates.single.attributes['name']!,
        fields: Map.unmodifiable(fields),
      );
    }
    return null;
  }

  static bool isSignInRedirect(String? location) {
    final path = Uri.tryParse(location ?? '')?.path ?? '';
    return path == '/signin' ||
        path.startsWith('/signin/') ||
        path == '/restricted';
  }

  /// `div.problem ul li` — the same shape for sign-in and 2FA failures.
  static List<String> parseErrors(String html) => parseProblemList(html);

  /// V2EX answers the sign-in POST with `302` to `/2fa` when the account has
  /// two-step verification enabled.
  static bool isTwoFactorRedirect(String? location) =>
      location != null && Uri.tryParse(location)?.path == '/2fa';
}
