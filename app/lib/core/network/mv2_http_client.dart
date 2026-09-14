import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../errors/failures.dart';
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

/// Serialises every outbound request and enforces a minimum gap between them.
///
/// V2EX has no published rate limit for the HTML surface and reacts to bursts
/// with anti-flood pages, so the client paces itself (`docs/12` §6, defect B5).
class _RequestPacer {
  _RequestPacer(this.minInterval);

  final Duration minInterval;
  Future<void> _tail = Future<void>.value();
  DateTime? _lastFinishedAt;

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _tail;
    _tail = completer.future;

    return Future<T>(() async {
      await previous;
      try {
        final last = _lastFinishedAt;
        if (last != null) {
          final elapsed = DateTime.now().difference(last);
          if (elapsed < minInterval) {
            await Future<void>.delayed(minInterval - elapsed);
          }
        }
        return await action();
      } finally {
        _lastFinishedAt = DateTime.now();
        completer.complete();
      }
    });
  }
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
  Future<HttpResult> get(
    String path, {
    Map<String, dynamic>? query,
    String? referer,
    String? baseUrl,
  }) {
    return _pacer.run(() async {
      try {
        final response = await _dio.get<String>(
          _absolute(path, baseUrl),
          queryParameters: query,
          options: Options(
            headers: _headers(referer: referer),
            responseType: ResponseType.plain,
          ),
        );
        return _toResult(response);
      } catch (error, stack) {
        throw mapError(error, stack);
      }
    });
  }

  /// GET a JSON endpoint. Returns the decoded map (or list, wrapped by the
  /// caller's parser).
  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
    String? referer,
  }) async {
    final result = await get(path, query: query, referer: referer);
    return decodeJson(result);
  }

  /// JSON endpoints on a different host (sov2ex).
  Future<dynamic> getJsonOn(
    String baseUrl,
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final result = await get(path, query: query, baseUrl: baseUrl);
    return decodeJson(result);
  }

  /// Form POST. `followRedirects` stays off so callers can inspect the `302`.
  Future<HttpResult> postForm(
    String path, {
    required Map<String, String> data,
    String? referer,
  }) {
    return _pacer.run(() async {
      try {
        final response = await _dio.post<String>(
          path,
          data: data,
          options: Options(
            headers: _headers(
              referer: referer,
              contentType: Headers.formUrlEncodedContentType,
            ),
            responseType: ResponseType.plain,
            followRedirects: false,
          ),
        );
        return _toResult(response);
      } catch (error, stack) {
        throw mapError(error, stack);
      }
    });
  }

  /// POST/PUT with no body (V2EX thank/ignore endpoints take `once` in the URL).
  Future<HttpResult> post(String path, {String? referer}) {
    return _pacer.run(() async {
      try {
        final response = await _dio.post<String>(
          path,
          options: Options(
            headers: _headers(referer: referer),
            responseType: ResponseType.plain,
            followRedirects: false,
          ),
        );
        return _toResult(response);
      } catch (error, stack) {
        throw mapError(error, stack);
      }
    });
  }

  /// Fetches raw bytes (captcha image).
  Future<List<int>> getBytes(String path, {String? referer}) {
    return _pacer.run(() async {
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
        throw mapError(error, stack);
      }
    });
  }

  Future<void> clearCookies() => _cookieJar.deleteAll();

  Future<List<Cookie>> cookiesFor(String url) =>
      _cookieJar.loadForRequest(Uri.parse(url));

  /// Seeds the jar from a WebView login flow (`docs/13` §6 decision).
  Future<void> seedCookie(String url, Cookie cookie) =>
      _cookieJar.saveFromResponse(Uri.parse(url), <Cookie>[cookie]);

  Map<String, dynamic> _headers({String? referer, String? contentType}) {
    return <String, dynamic>{'Referer': ?referer, 'Content-Type': ?contentType};
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

  dynamic decodeJson(HttpResult result) {
    if (!result.isSuccess) {
      throw _mapStatus(result.statusCode);
    }
    try {
      return jsonDecode(result.body);
    } on FormatException catch (error, stack) {
      throw ParseFailure(
        'JSON decode failed: ${result.body.length} bytes',
        cause: error,
        stackTrace: stack,
      );
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
  Failure mapError(Object error, StackTrace stack) {
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
