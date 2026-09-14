import 'dart:convert';

import '../../shared/models/write_result.dart';
import 'login_parser.dart';

/// Parses the response of V2EX's thank endpoints.
///
/// `/thank/topic/{id}` and `/thank/reply/{id}` break the usual write contract:
/// they answer **`200` with a small JSON body** (`{success, once, message}` —
/// the legacy `ThanksResult`) instead of the `302` every other write uses.
/// Treating the `200` as a rejection is what produced a false
/// `操作失败，请稍后重试。` on a *successful* 感谢.
///
/// Tolerated shapes, in order:
/// - empty `200` → success (some variants answer no body);
/// - `{"success": true}` / `{"success": false, "message": "…"}`;
/// - an HTML `div.problem ul li` block → those messages;
/// - anything else → a generic failure message.
abstract final class ThanksParser {
  /// Success payloads, plus the current `once` when the server rotates it.
  static V2WriteResult parse(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return const V2WriteResult(success: true);

    try {
      final json = jsonDecode(trimmed);
      if (json is Map) {
        final success = json['success'];
        if (success is bool) {
          // V2EX rotates the session `once`; keep the value it hands back.
          final once = _onceOf(json['once']);
          if (success) return V2WriteResult(success: true, once: once);
          final message = (json['message'] ?? '').toString().trim();
          return V2WriteResult(
            success: false,
            once: once,
            errors: <String>[message.isEmpty ? '感谢失败，请稍后重试。' : message],
          );
        }
      }
    } on FormatException {
      // Not JSON — fall through to the HTML problem parser.
    }

    final errors = LoginFormParser.parseErrors(trimmed);
    return V2WriteResult(
      success: false,
      errors: errors.isEmpty ? const <String>['感谢失败，请稍后重试。'] : errors,
    );
  }

  /// The refreshed token is an int in V2EX's payload; normalise to a string.
  static String? _onceOf(Object? raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    return value.isEmpty ? null : value;
  }
}
