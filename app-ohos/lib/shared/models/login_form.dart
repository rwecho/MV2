import 'package:flutter/foundation.dart';

/// The scraped V2EX sign-in form.
///
/// V2EX randomises the `name` attribute of every credential input on each
/// render (verified 2026-09-11: `03945380ef98…`, `a0dd3ecea3b4…`), so the field
/// names must be read from the page and echoed back on submit. This is why a
/// native form login has to scrape first — and why the old client stored the
/// whole `LoginParameters` object.
@immutable
class V2LoginForm {
  const V2LoginForm({
    required this.usernameFieldName,
    required this.passwordFieldName,
    required this.captchaFieldName,
    required this.once,
    required this.next,
    required this.captchaPath,
  });

  final String usernameFieldName;
  final String passwordFieldName;
  final String captchaFieldName;

  /// CSRF token for this form render.
  final String once;

  /// Post-login destination (`/`), echoed back in the hidden `next` input.
  final String next;

  /// Absolute URL of the captcha image (`/_captcha`).
  final String captchaPath;
}

/// Outcome of a sign-in attempt.
@immutable
class V2LoginResult {
  const V2LoginResult({
    required this.success,
    this.errors = const <String>[],
    this.twoFactor = false,
  });

  final bool success;

  /// Messages scraped from `div.problem ul li`.
  final List<String> errors;

  /// The server asked for the 2FA code.
  final bool twoFactor;
}
