import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../errors/failures.dart';
import '../telemetry/mv2_telemetry.dart';
import 'cookie_storage.dart';
import 'v2ex_endpoints.dart';

/// Raw HTTP outcome, deliberately transport-agnostic (no Dio types leak out).
class HttpResult {
  const HttpResult({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// V2EX signals a successful write with `302` + a changed `Location`; the
  /// redirect must NOT be followed automatically or the POST degrades to a GET
  /// (`docs/12` §1).
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  String? get location {
    final value = headers['location'];
    if (value == null || value.isEmpty) return null;
    return value.first;
  }
}

/// Scheduling class for paced requests. Declaration order is priority order:
/// writes go first, then reads someone is waiting on, prefetch last.
enum PacePriority { write, userRead, backgroundRead }

/// Serialises every outbound v2ex.com request and enforces a minimum gap
/// between them — exactly one request in flight at any time.
///
/// V2EX has no published rate limit for the HTML surface and reacts to bursts
/// with anti-flood pages, so the client paces itself (`docs/12` §6, defect B5).
/// The pending queue is priority-ordered: prefetch/idle work ([PacePriority.backgroundRead])
/// reorders behind whatever the user is waiting for, but priorities only ever
/// reorder the queue — they never widen it.
class _RequestPacer {
  _RequestPacer(this.minInterval);

  final Duration minInterval;

  final List<_PaceJob> _queue = <_PaceJob>[];
  bool _pumping = false;
  DateTime? _lastFinishedAt;

  /// Enqueues [action]; the returned future completes once the job has run,
  /// after every higher-priority job that arrived before it. [key] identifies
  /// the job for [upgrade].
  Future<T> run<T>(
    PacePriority priority,
    Future<T> Function() action, {
    String? key,
  }) {
    final completer = Completer<T>();
    _queue.add(
      _PaceJob(
        priority,
        () async {
          try {
            completer.complete(await action());
          } catch (error, stack) {
            completer.completeError(error, stack);
          }
        },
        key: key,
      ),
    );
    _pump();
    return completer.future;
  }

  /// Raises the queued job identified by [key] to at least [priority]. Lets a
  /// user-initiated request that joins an in-flight prefetch also jump ahead
  /// of the remaining background work instead of inheriting its slot.
  void upgrade(String key, PacePriority priority) {
    for (final job in _queue) {
      if (job.key == key && job.priority.index > priority.index) {
        job.priority = priority;
      }
    }
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        // Highest priority (lowest enum index) wins; ties stay FIFO because
        // the scan keeps the first match.
        var best = 0;
        for (var i = 1; i < _queue.length; i++) {
          if (_queue[i].priority.index < _queue[best].priority.index) {
            best = i;
          }
        }
        final job = _queue.removeAt(best);
        try {
          final last = _lastFinishedAt;
          if (last != null) {
            final elapsed = DateTime.now().difference(last);
            if (elapsed < minInterval) {
              await Future<void>.delayed(minInterval - elapsed);
            }
          }
          await job.execute();
        } catch (_) {
          // The job's own future already delivered the error to its callers.
        } finally {
          _lastFinishedAt = DateTime.now();
        }
      }
    } finally {
      _pumping = false;
    }
  }
}

class _PaceJob {
  _PaceJob(this.priority, this.execute, {required this.key});

  PacePriority priority;
  final Future<void> Function() execute;
  final String? key;
}

/// The MV2 HTTP client: cookie session, per-request Referer, no auto-redirect,
/// paced requests, and a single place where transport errors become [Failure]s.
class Mv2HttpClient {
  Mv2HttpClient(
    this._dio,
    this._cookieJar, {
    Duration minInterval = const Duration(milliseconds: 350),
  }) : _pacer = _RequestPacer(minInterval);

  /// Production client: persistent cookie jar in secure storage.
  ///
  /// [proxyUrl] (e.g. `http://127.0.0.1:7897`) routes every request through an
  /// HTTP proxy. It exists for development against `www.v2ex.com` from
  /// networks where the site is not directly reachable; it is supplied at build
  /// time via `--dart-define=MV2_PROXY=...` and defaults to no proxy.
  static Mv2HttpClient create({
    CookieJar? cookieJar,
    Storage? storage,
    String? proxyUrl,
  }) {
    final jar =
        cookieJar ??
        PersistCookieJar(storage: storage ?? SecureCookieStorage());
    final dio = Dio(
      BaseOptions(
        baseUrl: V2exEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        // Manual redirect handling is mandatory (see HttpResult.isRedirect).
        followRedirects: false,
        // Accept 2xx/3xx; 4xx/5xx are mapped to Failures below.
        validateStatus: (status) => status != null && status < 400,
        headers: <String, String>{
          'User-Agent': V2exEndpoints.userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ),
    )..interceptors.add(CookieManager(jar));

    final proxy = proxyUrl?.trim();
    if (proxy != null && proxy.isNotEmpty) {
      final uri = Uri.parse(proxy);
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
          return client;
        },
      );
    }

    return Mv2HttpClient(dio, jar);
  }

  final Dio _dio;
  final CookieJar _cookieJar;
  final _RequestPacer _pacer;

  /// GET returning the raw body.
  ///
  /// [referer] must be set for any request that follows a write action or that
  /// V2EX validates (topic detail, replies, favourites, ignore).
  /// [userAgent] overrides the session-default mobile UA (used by content
  /// writes so V2EX's `via` label matches the real device).
  /// [priority] only reorders the pacer queue (prefetches pass
  /// [PacePriority.backgroundRead]); it never changes the one-request-at-a-time
  /// guarantee.
  ///
  /// Identical in-flight GETs (same path, query, referer and UA) share one
  /// request — a user tap that races an idle prefetch rides its response
  /// instead of issuing a second one. Requests to a non-default [baseUrl]
  /// (sov2ex search) sit outside V2EX's anti-flood surface: no pacing, no
  /// single-flight.
  Future<HttpResult> get(
    String path, {
    Map<String, dynamic>? query,
    String? referer,
    String? baseUrl,
    String? userAgent,
    PacePriority priority = PacePriority.userRead,
  }) {
    if (baseUrl != null) {
      return _getRaw(
        path,
        query: query,
        referer: referer,
        baseUrl: baseUrl,
        userAgent: userAgent,
      );
    }
    final key = _flightKey(path, query, referer, userAgent);
    final existing = _inflightGets[key];
    if (existing != null) {
      _pacer.upgrade(key, priority);
      return existing;
    }
    final future = _pacer.run(
      priority,
      () => _getRaw(path, query: query, referer: referer, userAgent: userAgent),
      key: key,
    );
    _inflightGets[key] = future;
    future.whenComplete(() => _inflightGets.remove(key)).ignore();
    return future;
  }

  final Map<String, Future<HttpResult>> _inflightGets =
      <String, Future<HttpResult>>{};

  Future<HttpResult> _getRaw(
    String path, {
    Map<String, dynamic>? query,
    String? referer,
    String? baseUrl,
    String? userAgent,
  }) async {
    try {
      final response = await _dio.get<String>(
        _absolute(path, baseUrl),
        queryParameters: query,
        options: Options(
          headers: _headers(referer: referer, userAgent: userAgent),
          responseType: ResponseType.plain,
        ),
      );
      return _toResult(response);
    } catch (error, stack) {
      throw mapError(error, stack, path: path);
    }
  }

  /// Single-flight pool key. Referer and UA partition the pool because they
  /// change what V2EX serves for validated endpoints.
  String _flightKey(
    String path,
    Map<String, dynamic>? query,
    String? referer,
    String? userAgent,
  ) {
    final buffer = StringBuffer('GET $path');
    if (query != null && query.isNotEmpty) {
      final keys = query.keys.map((key) => key.toString()).toList()..sort();
      buffer
        ..write('?')
        ..write(keys.map((key) => '$key=${query[key]}').join('&'));
    }
    buffer.write('|referer=${referer ?? ''}|ua=${userAgent ?? ''}');
    return buffer.toString();
  }

  /// GET a JSON endpoint. Returns the decoded map (or list, wrapped by the
  /// caller's parser).
  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
    String? referer,
    PacePriority priority = PacePriority.userRead,
  }) async {
    final result = await get(
      path,
      query: query,
      referer: referer,
      priority: priority,
    );
    return decodeJson(result, path: path);
  }

  /// JSON endpoints on a different host (sov2ex). Unpaced — see [get].
  Future<dynamic> getJsonOn(
    String baseUrl,
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final result = await get(path, query: query, baseUrl: baseUrl);
    return decodeJson(result, path: path);
  }

  /// Form POST. `followRedirects` stays off so callers can inspect the `302`.
  /// [userAgent] overrides the session-default mobile UA (content writes pass
  /// the device-honest UA — see `V2exWriteUa`).
  Future<HttpResult> postForm(
    String path, {
    required Map<String, String> data,
    String? referer,
    String? userAgent,
  }) {
    return _pacer.run(PacePriority.write, () async {
      try {
        final response = await _dio.post<String>(
          path,
          data: data,
          options: Options(
            headers: _headers(
              referer: referer,
              contentType: Headers.formUrlEncodedContentType,
              userAgent: userAgent,
            ),
            responseType: ResponseType.plain,
            followRedirects: false,
          ),
        );
        return _toResult(response);
      } catch (error, stack) {
        throw mapError(error, stack, path: path);
      }
    });
  }

  /// JSON POST. `followRedirects` stays off like [postForm].
  ///
  /// [toleratesHttpErrors] keeps 4xx/5xx responses in the returned [HttpResult]
  /// instead of throwing: the Solana login endpoint answers every rejection as
  /// a status code + JSON `{"error": …}`, and the body is the actionable part.
  Future<HttpResult> postJson(
    String path, {
    required Map<String, dynamic> data,
    String? referer,
    bool toleratesHttpErrors = false,
  }) {
    return _pacer.run(PacePriority.write, () async {
      try {
        final response = await _dio.post<String>(
          path,
          data: data,
          options: Options(
            headers: _headers(
              referer: referer,
              contentType: Headers.jsonContentType,
            ),
            responseType: ResponseType.plain,
            followRedirects: false,
          ),
        );
        final status = response.statusCode ?? 0;
        if (status >= 400 && !toleratesHttpErrors) {
          throw _mapStatus(status);
        }
        return HttpResult(
          statusCode: status,
          body: response.data ?? '',
          headers: response.headers.map.map(
            (key, value) => MapEntry(key.toLowerCase(), value),
          ),
        );
      } catch (error, stack) {
        throw mapError(error, stack, path: path);
      }
    });
  }

  /// POST/PUT with no body (V2EX thank/ignore endpoints take `once` in the URL).
  Future<HttpResult> post(String path, {String? referer, String? userAgent}) {
    return _pacer.run(PacePriority.write, () async {
      try {
        final response = await _dio.post<String>(
          path,
          options: Options(
            headers: _headers(referer: referer, userAgent: userAgent),
            responseType: ResponseType.plain,
            followRedirects: false,
          ),
        );
        return _toResult(response);
      } catch (error, stack) {
        throw mapError(error, stack, path: path);
      }
    });
  }

  /// Fetches raw bytes (captcha image).
  Future<List<int>> getBytes(String path, {String? referer}) {
    return _pacer.run(PacePriority.userRead, () async {
      try {
        final response = await _dio.get<List<int>>(
          path,
          options: Options(
            headers: _headers(referer: referer),
            responseType: ResponseType.bytes,
          ),
        );
        if (response.statusCode == 404) {
          throw const NotFoundFailure();
        }
        return response.data ?? const <int>[];
      } catch (error, stack) {
        throw mapError(error, stack, path: path);
      }
    });
  }

  Future<void> clearCookies() => _cookieJar.deleteAll();

  Future<List<Cookie>> cookiesFor(String url) =>
      _cookieJar.loadForRequest(Uri.parse(url));

  /// Seeds the jar from a WebView login flow (`docs/13` §6 decision).
  Future<void> seedCookie(String url, Cookie cookie) =>
      _cookieJar.saveFromResponse(Uri.parse(url), <Cookie>[cookie]);

  Map<String, dynamic> _headers({
    String? referer,
    String? contentType,
    String? userAgent,
  }) {
    return <String, dynamic>{
      'Referer': ?referer,
      'Content-Type': ?contentType,
      // Absent when null: per-request headers merge over the base ones, so an
      // override only wins where one is supplied.
      'User-Agent': ?userAgent,
    };
  }

  HttpResult _toResult(Response<String> response) {
    final body = response.data ?? '';
    final status = response.statusCode ?? 0;

    if (status >= 400) {
      throw _mapStatus(status);
    }
    if (V2exLiterals.isRateLimited(body)) {
      throw const RateLimitFailure();
    }
    return HttpResult(
      statusCode: status,
      body: body,
      headers: response.headers.map.map(
        (key, value) => MapEntry(key.toLowerCase(), value),
      ),
    );
  }

  dynamic decodeJson(HttpResult result, {String path = '?'}) {
    if (!result.isSuccess) {
      throw _mapStatus(result.statusCode);
    }
    try {
      return jsonDecode(result.body);
    } on FormatException catch (error, stack) {
      final failure = ParseFailure(
        'JSON decode failed: ${result.body.length} bytes',
        cause: error,
        stackTrace: stack,
      );
      Mv2Telemetry.recordNonFatal(failure, stack, reason: 'GET $path');
      throw failure;
    }
  }

  /// Resolves [path] against a non-default host (sov2ex).
  String _absolute(String path, String? baseUrl) {
    if (baseUrl == null || path.startsWith('http')) return path;
    return '$baseUrl$path';
  }

  Failure _mapStatus(int status) {
    return switch (status) {
      401 || 403 => const AuthFailure(),
      404 => const NotFoundFailure(),
      429 => const RateLimitFailure(),
      >= 500 => const ServerFailure(),
      _ => UnknownFailure(message: '请求失败（HTTP $status）。'),
    };
  }

  /// Translates a transport-level error into a [Failure].
  ///
  /// Every translated failure is reported to Crashlytics as a non-fatal with
  /// the request path — the one observability hook shared by every feature
  /// (feed, notifications, nodes, search, …), so a device-specific outage like
  /// an anti-bot challenge or carrier interference shows up in the console
  /// with its real shape instead of a generic UI error state.
  Failure mapError(Object error, StackTrace stack, {String path = '?'}) {
    final failure = _mapError(error, stack);
    final status = error is DioException ? error.response?.statusCode : null;
    assert(() {
      // Debug-build only: surface the real failure shape on the console —
      // release reports go through Mv2Telemetry instead.
      debugPrint(
        'MV2 HTTP failure [$path]: ${failure.runtimeType}'
        '${status != null ? ' (HTTP $status)' : ''} ${failure.message}',
      );
      return true;
    }());
    Mv2Telemetry.recordNonFatal(
      failure,
      stack,
      reason: 'GET/POST $path'
          '${status != null ? ' [HTTP $status]' : ''}'
          ' ${failure.message}',
    );
    return failure;
  }

  Failure _mapError(Object error, StackTrace stack) {
    if (error is Failure) return error;
    if (error is DioException) {
      final status = error.response?.statusCode;
      final body = error.response?.data;
      if (status != null && status >= 400) {
        if (status == 403 || status == 401) return const AuthFailure();
        if (status == 404) return const NotFoundFailure();
        if (status == 429) return const RateLimitFailure();
        if (status >= 500) return const ServerFailure();
      }
      if (body is String && V2exLiterals.isRateLimited(body)) {
        return const RateLimitFailure();
      }
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => const NetworkFailure(
          message: '请求超时，请检查网络后重试。',
        ),
        DioExceptionType.connectionError ||
        DioExceptionType.badCertificate => const NetworkFailure(),
        _ => UnknownFailure(cause: error, stackTrace: stack),
      };
    }
    return UnknownFailure(cause: error, stackTrace: stack);
  }
}
