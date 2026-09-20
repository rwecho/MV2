import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failures.dart';

/// Standard MV2 write-action feedback.
///
/// `Failure` already carries a user-facing Chinese message; anything else falls
/// back to a generic line. Kept in one place so every page toasts identically.

/// Human-readable text for any thrown object.
String mv2DescribeError(Object error) {
  if (error is Failure) return error.message;
  return '出错了，请稍后重试。';
}

/// Shows the standard failure SnackBar, replacing any current one so repeated
/// failures do not queue up.
void mv2ShowError(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mv2DescribeError(error))));
}

/// Shows the short success confirmation for a completed write (已收藏, 已感谢,
/// …), replacing any current one so rapid actions never queue up.
///
/// Takes the [ScaffoldMessengerState] rather than a context so callers that pop
/// first (the composers) can capture it beforehand and still confirm after
/// their route is gone — the same reason `publish_topic_page` does.
void mv2ShowSuccess(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
}

/// Toasts a **first load** failure.
///
/// Call from a `ref.listen(provider, (previous, next) => …)` callback:
/// pull-to-refresh failures are toasted by `Mv2Refreshable` instead, so any
/// transition that already had a value or an error is skipped and the two never
/// double up on the same failure.
void mv2ToastLoadError(
  BuildContext context,
  AsyncValue<Object?>? previous,
  AsyncValue<Object?> next,
) {
  final error = next.error;
  if (error == null) return;
  final alreadyHadSomething =
      (previous?.hasValue ?? false) || (previous?.hasError ?? false);
  if (alreadyHadSomething) return;
  mv2ShowError(context, error);
}
