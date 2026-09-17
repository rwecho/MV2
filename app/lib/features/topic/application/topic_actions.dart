import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/session_once.dart';
import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/telemetry/mv2_analytics.dart';
import '../../../shared/models/topic_detail.dart';
import '../../../shared/models/write_result.dart';
import 'topic_providers.dart';

/// Overlay state for the topic actions that the server page cannot express
/// optimistically: 收藏, 感谢 (topic and per reply) and 忽略.
///
/// The authoritative flags still come from [V2TopicDetail]; a non-null field
/// here is an optimistic override that wins until the request settles (and is
/// rolled back on failure).
@immutable
class TopicActionsState {
  const TopicActionsState({
    this.favorited,
    this.thanked,
    this.ignored,
    this.thankedReplies = const <String>{},
    this.ignoredReplies = const <String>{},
    this.inFlight = const <String>{},
    this.failure,
  });

  /// `null` means "use the value scraped from the detail page".
  final bool? favorited;
  final bool? thanked;
  final bool? ignored;

  /// Reply ids whose 感谢 is being applied optimistically.
  final Set<String> thankedReplies;

  /// Reply ids whose 忽略 is being applied optimistically.
  final Set<String> ignoredReplies;

  /// Action keys currently awaiting a response; guards against double taps.
  final Set<String> inFlight;

  /// Last failure, kept so the UI can surface the exact message. Cleared when a
  /// new action starts.
  final Failure? failure;

  /// User-facing message of [failure], if any.
  String? get errorMessage => failure?.message;

  /// True when the last failure was a missing/expired session, so the UI can
  /// route to `/login` instead of only showing a message.
  bool get authRequired => failure is AuthFailure;

  bool isInFlight(String key) => inFlight.contains(key);

  /// Effective flags: the optimistic override when present, else the value
  /// scraped from the detail page.
  bool favoritedOf(bool serverValue) => favorited ?? serverValue;
  bool thankedOf(bool serverValue) => thanked ?? serverValue;
  bool ignoredOf(bool serverValue) => ignored ?? serverValue;

  TopicActionsState copyWith({
    bool? favorited,
    bool? thanked,
    bool? ignored,
    Set<String>? thankedReplies,
    Set<String>? ignoredReplies,
    Set<String>? inFlight,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return TopicActionsState(
      favorited: favorited ?? this.favorited,
      thanked: thanked ?? this.thanked,
      ignored: ignored ?? this.ignored,
      thankedReplies: thankedReplies ?? this.thankedReplies,
      ignoredReplies: ignoredReplies ?? this.ignoredReplies,
      inFlight: inFlight ?? this.inFlight,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

/// Owns the optimistic 收藏 / 感谢 / 忽略 state for one topic.
///
/// Every mutation follows the same contract:
/// 1. refuse to run when the same action is already in flight (double-tap
///    guard);
/// 2. refuse to run without a `once` token — a request is never sent for a
///    signed-out session, and [AuthFailure] is surfaced instead;
/// 3. apply the optimistic value, then request;
/// 4. roll the optimistic value back on failure and record the [Failure].
class TopicActionsController extends Notifier<TopicActionsState> {
  TopicActionsController(this.topicId);

  final int topicId;

  /// In-flight keys. Reply-scoped keys append the reply id.
  static const String favoriteKey = 'favorite';
  static const String thankKey = 'thank';
  static const String ignoreKey = 'ignore';
  static String thankReplyKey(String replyId) => 'thank_reply:$replyId';
  static String ignoreReplyKey(String replyId) => 'ignore_reply:$replyId';

  @override
  TopicActionsState build() {
    // Every render of a page with a `once` input overwrites the session's
    // token, so treat the freshest scrape as the current one.
    ref.listen(topicDetailProvider(TopicDetailArgs(topicId)), (previous, next) {
      ref.read(sessionOnceProvider.notifier).update(next.value?.once);
    });
    return const TopicActionsState();
  }

  /// The CSRF token for this session: the newest rotated value when a write has
  /// already happened, otherwise the one scraped from the topic page. `null`
  /// means signed out (or the detail page has not loaded yet), in which case no
  /// write may be attempted.
  String? get once {
    final rotated = ref.read(sessionOnceProvider);
    final base = ref
        .read(topicDetailProvider(TopicDetailArgs(topicId)))
        .value
        ?.once;
    final token = rotated ?? base;
    return (token == null || token.isEmpty) ? null : token;
  }

  V2TopicDetail? get _detail =>
      ref.read(topicDetailProvider(TopicDetailArgs(topicId))).value;

  bool replyThanked(String replyId, bool serverValue) =>
      state.thankedReplies.contains(replyId) || serverValue;

  /// 埋点结果映射:写入终态 → success / failed / auth_required。
  String _resultOf(Failure? failure) =>
      failure == null ? 'success' : (failure is AuthFailure ? 'auth_required' : 'failed');

  /// Toggles 收藏 / 取消收藏.
  Future<Failure?> toggleFavorite() async {
    if (state.isInFlight(favoriteKey)) return null;
    final token = once;
    if (token == null) {
      final failure = _requireAuth();
      Mv2Analytics.logTopicFavorite(
        topicId: topicId,
        enabled: !(state.favorited ?? (_detail?.favorited ?? false)),
        result: 'auth_required',
      );
      return failure;
    }
    final detail = _detail;
    final target = !(state.favorited ?? (detail?.favorited ?? false));
    _start(favoriteKey, favorited: target);
    final failure = await _run(
      key: favoriteKey,
      initialToken: token,
      request: (String t) => target
          ? ref.read(v2exApiProvider).favoriteTopic(topicId, t)
          : ref.read(v2exApiProvider).unfavoriteTopic(topicId, t),
      rollback: () => state = state.copyWith(favorited: !target),
    );
    Mv2Analytics.logTopicFavorite(
      topicId: topicId,
      enabled: target,
      result: _resultOf(failure),
    );
    return failure;
  }

  /// Thanks the topic. V2EX thanks cannot be withdrawn, so a second tap on an
  /// already-thanked topic is a no-op rather than a toggle.
  Future<Failure?> thankTopic() async {
    if (state.isInFlight(thankKey)) return null;
    final token = once;
    if (token == null) {
      final failure = _requireAuth();
      Mv2Analytics.logTopicThank(topicId: topicId, result: 'auth_required');
      return failure;
    }
    final detail = _detail;
    if (state.thanked ?? (detail?.thanked ?? false)) return null;
    _start(thankKey, thanked: true);
    final failure = await _run(
      key: thankKey,
      initialToken: token,
      request: (String t) => ref.read(v2exApiProvider).thankTopic(topicId, t),
      rollback: () => state = state.copyWith(thanked: false),
    );
    Mv2Analytics.logTopicThank(topicId: topicId, result: _resultOf(failure));
    return failure;
  }

  /// Thanks a single reply by its V2EX reply id.
  Future<Failure?> thankReply(String replyId) async {
    final key = thankReplyKey(replyId);
    if (state.isInFlight(key)) return null;
    final token = once;
    if (token == null) return _requireAuth();
    _start(key, thankedReplies: <String>{...state.thankedReplies, replyId});
    return _run(
      key: key,
      initialToken: token,
      request: (String t) => ref.read(v2exApiProvider).thankReply(replyId, t),
      rollback: () => state = state.copyWith(
        thankedReplies: <String>{...state.thankedReplies}..remove(replyId),
      ),
    );
  }

  /// Toggles 忽略 / 取消忽略 for the topic.
  Future<Failure?> toggleIgnore() async {
    if (state.isInFlight(ignoreKey)) return null;
    final token = once;
    if (token == null) {
      final failure = _requireAuth();
      Mv2Analytics.logTopicIgnore(
        topicId: topicId,
        enabled: !(state.ignored ?? (_detail?.ignored ?? false)),
        result: 'auth_required',
      );
      return failure;
    }
    final detail = _detail;
    final target = !(state.ignored ?? (detail?.ignored ?? false));
    _start(ignoreKey, ignored: target);
    final failure = await _run(
      key: ignoreKey,
      initialToken: token,
      request: (String t) => target
          ? ref.read(v2exApiProvider).ignoreTopic(topicId, t)
          : ref.read(v2exApiProvider).unignoreTopic(topicId, t),
      rollback: () => state = state.copyWith(ignored: !target),
    );
    Mv2Analytics.logTopicIgnore(
      topicId: topicId,
      enabled: target,
      result: _resultOf(failure),
    );
    return failure;
  }

  /// Ignores a single reply.
  Future<Failure?> ignoreReply(String replyId) async {
    final key = ignoreReplyKey(replyId);
    if (state.isInFlight(key)) return null;
    final token = once;
    if (token == null) return _requireAuth();
    _start(key, ignoredReplies: <String>{...state.ignoredReplies, replyId});
    return _run(
      key: key,
      initialToken: token,
      request: (String t) => ref.read(v2exApiProvider).ignoreReply(replyId, t),
      rollback: () => state = state.copyWith(
        ignoredReplies: <String>{...state.ignoredReplies}..remove(replyId),
      ),
    );
  }

  /// Marks an optimistic value **and** registers the in-flight key before the
  /// first `await`, which is what makes the double-tap guard synchronous.
  void _start(
    String key, {
    bool? favorited,
    bool? thanked,
    bool? ignored,
    Set<String>? thankedReplies,
    Set<String>? ignoredReplies,
  }) {
    state = state.copyWith(
      favorited: favorited,
      thanked: thanked,
      ignored: ignored,
      thankedReplies: thankedReplies,
      ignoredReplies: ignoredReplies,
      inFlight: <String>{...state.inFlight, key},
      clearFailure: true,
    );
  }

  /// Runs one write, reusing the rotated token V2EX hands back.
  ///
  /// `once` is **not** a stable session token: every page render generates a
  /// fresh value and overwrites the one stored in `PB3_SESSION`, so any other
  /// page fetch (home, reply pagination, …) silently invalidates the token we
  /// hold. The `/thank/*` endpoints hand the new value back, but
  /// favourite/ignore answer `302` with no token, so the next action can start
  /// from a stale one.
  ///
  /// Any rejection is therefore retried **once** with a freshly scraped token.
  /// A stale token can surface as a CSRF problem page, a generic rejection or
  /// even a `/signin` redirect, which is not reliably distinguishable from a
  /// real failure; the retry re-sends the *same* target action (toggles are
  /// idempotent), so it can only turn a false rejection into a success.
  /// Rate limits are never retried.
  Future<Failure?> _run({
    required String key,
    required String initialToken,
    required Future<V2WriteResult> Function(String once) request,
    required void Function() rollback,
  }) async {
    try {
      var token = initialToken;
      var attempt = await _attempt(request, token);
      ref.read(sessionOnceProvider.notifier).update(attempt.result?.once);
      if (attempt.succeeded) return null;

      if (attempt.failure is! RateLimitFailure) {
        debugPrint(
          'MV2: write failed '
          '(${attempt.failure?.message ?? attempt.result?.errors}) — '
          're-scraping once and retrying',
        );
        final fresh = await _refreshOnce();
        if (fresh != null && fresh != token) {
          token = fresh;
          attempt = await _attempt(request, token);
          ref.read(sessionOnceProvider.notifier).update(attempt.result?.once);
          if (attempt.succeeded) return null;
        }
      }

      rollback();
      final failure = attempt.failure;
      if (failure != null) return _fail(failure);
      return _fail(_rejected(attempt.result!));
    } catch (error, stack) {
      // `_attempt` captures every `Failure`, so anything landing here is
      // unexpected; still roll back and surface it instead of leaving the
      // optimistic state applied with no message.
      rollback();
      return _fail(
        error is Failure
            ? error
            : UnknownFailure(cause: error, stackTrace: stack),
      );
    } finally {
      state = state.copyWith(
        inFlight: <String>{...state.inFlight}..remove(key),
      );
    }
  }

  /// One write attempt: the transport-level [Failure] is captured instead of
  /// thrown so the caller can decide whether a fresh-token retry is worthwhile.
  Future<_WriteAttempt> _attempt(
    Future<V2WriteResult> Function(String once) request,
    String token,
  ) async {
    try {
      return _WriteAttempt(result: await request(token));
    } on Failure catch (failure) {
      return _WriteAttempt(failure: failure);
    }
  }

  ActionRejectedFailure _rejected(V2WriteResult result) =>
      ActionRejectedFailure(
        result.errors.isEmpty ? '操作失败，请稍后重试。' : result.errors.first,
      );

  /// Fetches a freshly rendered topic page so the session holds a token issued
  /// *now*, and returns it.
  ///
  /// Deliberately bypasses `topicDetailProvider`: invalidating it would swap
  /// the visible page for the loading skeleton, unmount [_TopicDetailBody]'s
  /// `failure` listener and swallow the rejection we are about to surface —
  /// which looked like the action silently doing nothing.
  Future<String?> _refreshOnce() async {
    try {
      final detail = await ref.read(v2exApiProvider).topicDetail(topicId);
      final token = detail.once;
      if (token == null || token.isEmpty) return null;
      ref.read(sessionOnceProvider.notifier).update(token);
      return token;
    } catch (_) {
      // Best effort: without a fresh token we simply surface the original
      // rejection rather than crashing the action.
      return null;
    }
  }

  Failure _fail(Failure failure) {
    state = state.copyWith(failure: failure);
    return failure;
  }

  /// Signed-out path: never send without a token.
  Failure _requireAuth() {
    const failure = AuthFailure();
    state = state.copyWith(failure: failure);
    return failure;
  }
}

/// Per-topic action state; keyed by the topic id.
final topicActionsProvider =
    NotifierProvider.family<TopicActionsController, TopicActionsState, int>(
      TopicActionsController.new,
    );

/// Outcome of a single write attempt: either a parsed [V2WriteResult] or the
/// transport-level [Failure] that was thrown.
@immutable
class _WriteAttempt {
  const _WriteAttempt({this.result, this.failure});

  final V2WriteResult? result;
  final Failure? failure;

  bool get succeeded => result?.success ?? false;
}
