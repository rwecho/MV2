import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/core/network/v2ex_endpoints.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/topic/presentation/topic_detail_page.dart';
import 'package:mv2/shared/models/topic_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replays a canned redirect without touching the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status, this.location);

  final int status;
  final String? location;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      // V2EX's restricted redirect carries an empty body.
      '',
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
        if (location != null) 'location': <String>[location!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

RemoteV2exApi _apiFor(int status, String? location) {
  final dio = Dio(
    BaseOptions(
      baseUrl: V2exEndpoints.baseUrl,
      followRedirects: false,
      validateStatus: (value) => value != null && value < 400,
    ),
  )..httpClientAdapter = _FakeAdapter(status, location);
  return RemoteV2exApi(Mv2HttpClient(dio, CookieJar()));
}

/// Throws on every topic request, to drive the page's error branch through the
/// real provider (not an override of it).
class _AuthFailingApi extends FixtureV2exApi {
  _AuthFailingApi() : super(latency: Duration.zero);

  @override
  Future<V2TopicDetail> topicDetail(int topicId, {int page = 1}) async {
    throw const AuthFailure(message: '该主题需要登录后查看。');
  }
}

void main() {
  group('restricted topic redirect', () {
    test('302 → /restricted is an AuthFailure, not a parse error', () async {
      await expectLater(
        _apiFor(302, '/restricted').topicDetail(1241298),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('302 → /signin?next=/restricted is an AuthFailure', () async {
      await expectLater(
        _apiFor(302, '/signin?next=/restricted').topicDetail(1241298),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('a non-auth redirect is a NotFoundFailure', () async {
      await expectLater(
        _apiFor(302, '/somewhere-else').topicDetail(1241298),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  testWidgets('the topic page offers 去登录 for a restricted topic', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer(
      overrides: [
        // Exercise the real `topicDetailProvider` (including its retry policy)
        // by failing the API instead of overriding the provider.
        v2exApiProvider.overrideWithValue(_AuthFailingApi()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const TopicDetailPage(topicId: 1241298),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('该主题需要登录后查看'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    // The retry affordance must not be offered for a state retrying cannot fix.
    expect(find.text('重试'), findsNothing);
  });
}
