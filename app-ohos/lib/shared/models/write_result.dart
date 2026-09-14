import 'package:flutter/foundation.dart';

/// Outcome of a V2EX write action that has no richer payload of its own.
///
/// A dedicated type is used instead of reusing `V2LoginResult`: the login
/// result carries a `twoFactor` flag that is meaningless for replies, thanks,
/// favourites and ignores, and reusing it would invite the UI to branch on a
/// field that can never be set here.
///
/// V2EX signals success with `302` and reports a rejection as a `200` page
/// carrying the same `div.problem ul li` block as the sign-in form
/// (`docs/12-v2ex-api-inventory.md` §4).
@immutable
class V2WriteResult {
  const V2WriteResult({
    required this.success,
    this.errors = const <String>[],
    this.once,
  });

  final bool success;

  /// Messages scraped from `div.problem ul li` when the action was rejected.
  /// Empty on success.
  final List<String> errors;

  /// Refreshed CSRF token, when the endpoint returns one.
  ///
  /// V2EX rotates the session `once` and hands the new value back in the
  /// `/thank/*` JSON (`{success, once, message}`). Callers must reuse it for the
  /// next write, otherwise the *second* action in a row is rejected.
  final String? once;

  /// True when the rejection looks like a rotated/expired CSRF token, which a
  /// page re-scrape plus a single retry can fix.
  ///
  /// An unparsable rejection (no `div.problem` block) is treated as probable:
  /// the rotated-token answer has no problem list.
  bool get looksLikeOnceFailure {
    if (success) return false;
    if (errors.isEmpty) return true;
    final text = errors.join(' ').toLowerCase();
    return text.contains('csrf') ||
        text.contains('once') ||
        text.contains('无效') ||
        text.contains('刷新');
  }
}
