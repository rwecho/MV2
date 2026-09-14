/// MV2 unified failure model (`docs/03-technical-architecture.md` §7).
///
/// The UI only ever reacts to these types — it must never see a `DioException`,
/// a status code, or a stack trace.
sealed class Failure implements Exception {
  const Failure(this.message, {this.cause, this.stackTrace});

  /// User-facing, already-localised (Simplified Chinese) message.
  final String message;

  /// Original error, for logging only.
  final Object? cause;
  final StackTrace? stackTrace;

  /// Whether re-running the same request could plausibly succeed.
  bool get isRetryable => switch (this) {
    NetworkFailure() => true,
    ServerFailure() => true,
    RateLimitFailure() => true,
    _ => false,
  };

  @override
  String toString() => '$runtimeType($message)';
}

/// No connectivity, DNS failure, timeout, or connection reset.
class NetworkFailure extends Failure {
  const NetworkFailure({
    String message = '网络连接失败，请检查网络后重试。',
    super.cause,
    super.stackTrace,
  }) : super(message);
}

/// 401 / 403 / missing session — the user must sign in.
class AuthFailure extends Failure {
  const AuthFailure({
    String message = '登录状态已失效，请重新登录。',
    super.cause,
    super.stackTrace,
  }) : super(message);
}

/// 404 — topic/node/member genuinely does not exist.
class NotFoundFailure extends Failure {
  const NotFoundFailure({
    String message = '内容不存在或已被删除。',
    super.cause,
    super.stackTrace,
  }) : super(message);
}

/// V2EX refused the action (anti-flood, permission, business rule).
class RateLimitFailure extends Failure {
  const RateLimitFailure({
    String message = '操作过于频繁，请稍后再试。',
    super.cause,
    super.stackTrace,
  }) : super(message);
}

/// 5xx from V2EX.
class ServerFailure extends Failure {
  const ServerFailure({
    String message = 'V2EX 服务暂时不可用，请稍后重试。',
    super.cause,
    super.stackTrace,
  }) : super(message);
}

/// The page/JSON shape was not what the parser expects — the site probably
/// changed. Distinct from [ServerFailure] because it must be surfaced loudly in
/// logs and never silently rendered as empty content.
class ParseFailure extends Failure {
  const ParseFailure(this.detail, {super.cause, super.stackTrace})
    : super('数据解析失败，页面结构可能已变更。');

  final String detail;

  @override
  String toString() => 'ParseFailure($detail)';
}

/// Anything we failed to classify.
class UnknownFailure extends Failure {
  const UnknownFailure({
    String message = '发生未知错误，请重试。',
    super.cause,
    super.stackTrace,
  }) : super(message);
}

/// 200-with-error-body responses from V2EX write endpoints (`Problem` blocks).
class ActionRejectedFailure extends Failure {
  const ActionRejectedFailure(super.message, {super.cause, super.stackTrace});
}
