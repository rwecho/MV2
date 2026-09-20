import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/core/network/v2ex_endpoints.dart';
import 'package:mv2/core/storage/http_cache.dart';

/// Records every request and replays canned responses, so the transport rules
/// (no auto-redirect, per-request Referer, UA, failure mapping) are covered
/// without touching the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final FutureOr<ResponseBody> Function(RequestOptions options) responder;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _html(
  String body, {
  int status = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    body,
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      ...?headers,
    },
  );
}

Mv2HttpClient _clientWith(_FakeAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: V2exEndpoints.baseUrl,
      followRedirects: false,
      validateStatus: (status) => status != null && status < 400,
      headers: <String, String>{'User-Agent': V2exEndpoints.userAgent},
    ),
  )..httpClientAdapter = adapter;
  return Mv2HttpClient(dio, CookieJar());
}

void main() {
  group('HttpCache policy', () {
    test('caches anonymous read paths only', () {
      expect(HttpCache.isCacheable('/'), isTrue);
      expect(HttpCache.isCacheable('/recent'), isTrue);
      expect(HttpCache.isCacheable('/t/123'), isTrue);
      expect(HttpCache.isCacheable('/t/123?p=2'), isTrue);
      expect(HttpCache.isCacheable('/go/python'), isTrue);
      expect(HttpCache.isCacheable('/tag/flutter'), isTrue);
      expect(HttpCache.isCacheable('/api/topics/hot.json'), isTrue);

      // Anything carrying account state must never be shared on disk.
      expect(HttpCache.isCacheable('/t/123/append'), isFalse);
      expect(HttpCache.isCacheable('/my/topics'), isFalse);
      expect(HttpCache.isCacheable('/notifications'), isFalse);
      expect(HttpCache.isCacheable('/mission/daily'), isFalse);
      expect(HttpCache.isCacheable('/settings/ignore/node/1'), isFalse);
      expect(HttpCache.isCacheable('/signin'), isFalse);
      expect(HttpCache.isCacheable('/new'), isFalse);
    });
  });

  group('Mv2HttpClient transport rules', () {
    test('sends the mobile UA and a per-request Referer', () async {
      final adapter = _FakeAdapter((_) => _html('<html></html>'));
      final client = _clientWith(adapter);

      await client.get('/t/1', referer: 'https://www.v2ex.com/');

      final request = adapter.requests.single;
      expect(request.headers['User-Agent'], V2exEndpoints.userAgent);
      expect(request.headers['Referer'], 'https://www.v2ex.com/');
    });

    test('a per-request UA override replaces the session default', () async {
      final adapter = _FakeAdapter((_) => _html('<html></html>'));
      final client = _clientWith(adapter);

      await client.get('/t/1', userAgent: 'UA-override');
      await client.get('/t/2');

      expect(adapter.requests[0].headers['User-Agent'], 'UA-override');
      expect(
        adapter.requests[1].headers['User-Agent'],
        V2exEndpoints.userAgent,
      );
    });

    test(
      'does not follow redirects so write results stay inspectable',
      () async {
        final adapter = _FakeAdapter(
          (_) => _html(
            '',
            status: 302,
            headers: <String, List<String>>{
              'location': <String>['/t/1'],
            },
          ),
        );
        final client = _clientWith(adapter);

        final result = await client.postForm(
          '/t/1',
          data: <String, String>{'content': 'hi'},
        );

        expect(result.isRedirect, isTrue);
        expect(result.location, '/t/1');
        expect(adapter.requests.single.followRedirects, isFalse);
      },
    );

    test('maps status codes onto the MV2 failure model', () async {
      Future<Failure> failureFor(int status) async {
        final adapter = _FakeAdapter((_) => _html('nope', status: status));
        final client = _clientWith(adapter);
        try {
          await client.get('/t/1');
          fail('expected a failure for $status');
        } on Failure catch (failure) {
          return failure;
        }
      }

      expect(await failureFor(403), isA<AuthFailure>());
      expect(await failureFor(401), isA<AuthFailure>());
      expect(await failureFor(404), isA<NotFoundFailure>());
      expect(await failureFor(429), isA<RateLimitFailure>());
      expect(await failureFor(503), isA<ServerFailure>());
    });

    test('detects the anti-flood page even on HTTP 200', () async {
      final adapter = _FakeAdapter((_) => _html('<div>操作过于频繁，请稍后再试</div>'));
      final client = _clientWith(adapter);

      expect(client.get('/t/1'), throwsA(isA<RateLimitFailure>()));
    });

    test('maps timeouts onto NetworkFailure', () async {
      final adapter = _FakeAdapter(
        (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      );
      final client = _clientWith(adapter);

      expect(client.get('/t/1'), throwsA(isA<NetworkFailure>()));
    });

    test('decodes JSON payloads', () async {
      final adapter = _FakeAdapter(
        (_) => ResponseBody.fromString(
          jsonEncode(<String, dynamic>{'ok': true}),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        ),
      );
      final client = _clientWith(adapter);

      final json = await client.getJson('/api/topics/hot.json');
      expect(json, <String, dynamic>{'ok': true});
    });

    test('surfaces malformed JSON as ParseFailure', () async {
      final adapter = _FakeAdapter((_) => _html('not json at all'));
      final client = _clientWith(adapter);

      expect(
        client.getJson('/api/topics/hot.json'),
        throwsA(isA<ParseFailure>()),
      );
    });
  });

  group('request pacer', () {
    /// Adapter whose responses wait on a per-path gate, so a request can be
    /// held "in flight" while the queue builds up behind it.
    ({_FakeAdapter adapter, Map<String, Completer<void>> gates})
    gatedAdapter() {
      final gates = <String, Completer<void>>{};
      final adapter = _FakeAdapter((options) {
        final path = options.uri.path;
        final gate = gates.putIfAbsent(path, Completer<void>.new);
        return gate.future.then(
          (_) => _html('<html>${Uri.encodeComponent(path)}</html>'),
        );
      });
      return (adapter: adapter, gates: gates);
    }

    Dio dioFor(_FakeAdapter adapter) {
      return Dio(
        BaseOptions(
          baseUrl: V2exEndpoints.baseUrl,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
          headers: <String, String>{'User-Agent': V2exEndpoints.userAgent},
        ),
      )..httpClientAdapter = adapter;
    }

    Future<void> pollUntil(bool Function() condition) async {
      const timeout = Duration(seconds: 5);
      final deadline = DateTime.now().add(timeout);
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('condition not met within $timeout');
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    test('a queued user read jumps ahead of earlier background work', () async {
      final (:adapter, :gates) = gatedAdapter();
      final client = Mv2HttpClient(
        dioFor(adapter),
        CookieJar(),
        minInterval: Duration.zero,
      );

      // Occupies the single execution slot.
      final first = client.get('/t/1');
      await pollUntil(() => adapter.requests.any((r) => r.uri.path == '/t/1'));

      // Enqueued behind it: background first, then a user read. FIFO would
      // run /t/2 before /t/3 — priority must flip them.
      final background = client.get(
        '/t/2',
        priority: PacePriority.backgroundRead,
      );
      final user = client.get('/t/3');

      gates['/t/1']!.complete();
      await first;
      await pollUntil(() => adapter.requests.any((r) => r.uri.path == '/t/3'));
      // /t/2 must still be parked behind the gated /t/3.
      expect(
        adapter.requests.where((r) => r.uri.path == '/t/2'),
        isEmpty,
      );

      gates['/t/3']!.complete();
      await user;
      await pollUntil(() => adapter.requests.any((r) => r.uri.path == '/t/2'));
      gates['/t/2']!.complete();
      await background;

      final started = adapter.requests.map((r) => r.uri.path).toList();
      expect(started.indexOf('/t/3'), lessThan(started.indexOf('/t/2')));
    });

    test('a queued write preempts both reads', () async {
      final (:adapter, :gates) = gatedAdapter();
      final client = Mv2HttpClient(
        dioFor(adapter),
        CookieJar(),
        minInterval: Duration.zero,
      );

      final first = client.get('/t/1');
      await pollUntil(() => adapter.requests.any((r) => r.uri.path == '/t/1'));

      final background = client.get(
        '/t/2',
        priority: PacePriority.backgroundRead,
      );
      final user = client.get('/t/3');
      final write = client.post('/thank/topic/9');

      // Release the running read; the write must be the next to start, then
      // the user read, and the background prefetch last.
      gates['/t/1']!.complete();
      await first;
      await pollUntil(
        () => adapter.requests.any((r) => r.uri.path == '/thank/topic/9'),
      );

      gates['/thank/topic/9']!.complete();
      await write;
      await pollUntil(() => adapter.requests.any((r) => r.uri.path == '/t/3'));

      gates['/t/3']!.complete();
      await user;
      await pollUntil(() => adapter.requests.any((r) => r.uri.path == '/t/2'));

      gates['/t/2']!.complete();
      await background;

      expect(
        adapter.requests.map((r) => r.uri.path).toList(),
        <String>['/t/1', '/thank/topic/9', '/t/3', '/t/2'],
      );
    });

    test('identical in-flight GETs share one request', () async {
      final adapter = _FakeAdapter((_) => _html('<html>ok</html>'));
      final client = Mv2HttpClient(
        dioFor(adapter),
        CookieJar(),
        minInterval: Duration.zero,
      );

      final results = await Future.wait(<Future<HttpResult>>[
        client.get('/t/1'),
        client.get('/t/1'),
      ]);

      expect(adapter.requests, hasLength(1));
      expect(results[0].body, '<html>ok</html>');
      expect(results[1].body, '<html>ok</html>');

      // After completion the pool entry is gone: a later call re-requests.
      await client.get('/t/1');
      expect(adapter.requests, hasLength(2));
    });

    test('different referers do not share a flight', () async {
      final adapter = _FakeAdapter((_) => _html('<html>ok</html>'));
      final client = Mv2HttpClient(
        dioFor(adapter),
        CookieJar(),
        minInterval: Duration.zero,
      );

      await Future.wait(<Future<void>>[
        client.get('/t/1', referer: 'https://www.v2ex.com/'),
        client.get('/t/1'),
      ]);

      expect(adapter.requests, hasLength(2));
    });

    test('a user request joining a queued prefetch promotes it', () async {
      final (:adapter, :gates) = gatedAdapter();
      final client = Mv2HttpClient(
        dioFor(adapter),
        CookieJar(),
        minInterval: Duration.zero,
      );

      final first = client.get('/t/1');
      await pollUntil(() => adapter.requests.any((r) => r.uri.path == '/t/1'));

      final background = client.get(
        '/t/2',
        priority: PacePriority.backgroundRead,
      );
      final otherUser = client.get('/t/3');
      // Same path/flight as the background prefetch — the joiner promotes it
      // so it runs before /t/3 instead of after.
      final joiner = client.get('/t/2');

      gates['/t/1']!.complete();
      await first;
      await pollUntil(() => adapter.requests.any((r) => r.uri.path == '/t/2'));
      expect(
        adapter.requests.where((r) => r.uri.path == '/t/3'),
        isEmpty,
      );

      gates['/t/2']!.complete();
      await Future.wait(<Future<void>>[background, joiner]);
      await pollUntil(() => adapter.requests.any((r) => r.uri.path == '/t/3'));
      gates['/t/3']!.complete();
      await otherUser;

      final started = adapter.requests.map((r) => r.uri.path).toList();
      expect(started.indexOf('/t/2'), lessThan(started.indexOf('/t/3')));
    });

    test('foreign-host requests skip the pacer entirely', () async {
      final adapter = _FakeAdapter((_) => _html('<html>ok</html>'));
      final client = Mv2HttpClient(
        dioFor(adapter),
        CookieJar(),
        // Any real wait would blow way past this budget.
        minInterval: const Duration(seconds: 30),
      );

      final stopwatch = Stopwatch()..start();
      await client.get('/api/search', baseUrl: 'https://sov2ex.example');
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('the minimum gap still separates consecutive requests', () async {
      final adapter = _FakeAdapter((_) => _html('<html>ok</html>'));
      final client = Mv2HttpClient(
        dioFor(adapter),
        CookieJar(),
        minInterval: const Duration(milliseconds: 500),
      );

      await client.get('/t/1');
      final stopwatch = Stopwatch()..start();
      await client.get('/t/2');
      stopwatch.stop();

      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 400)),
      );
    });
  });
}
