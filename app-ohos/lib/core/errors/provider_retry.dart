import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'failures.dart';

/// Riverpod 3 retries **every** `Exception` by default (10 attempts, up to
/// ~38 s of exponential backoff). MV2's own failure model already says what is
/// worth retrying ([Failure.isRetryable]); honour it so a login-required
/// (`AuthFailure`), missing (`NotFoundFailure`) or parse failure reaches the
/// page immediately instead of sitting in the retry delay. During that delay
/// the `AsyncValue` is an `AsyncLoading` that still carries the error, so
/// `when(loading:, error:)` keeps rendering the skeleton — a restricted topic
/// (V2EX answers `302 → /restricted`) looked like an infinite load instead of a
/// sign-in prompt.
///
/// Pass it as the `retry:` argument of any `FutureProvider` that reads from the
/// network (see `topic_providers.dart`, `feed_providers.dart`, …).
Duration? mv2Retry(int retryCount, Object error) {
  if (error is Failure && !error.isRetryable) return null;
  return ProviderContainer.defaultRetry(retryCount, error);
}
