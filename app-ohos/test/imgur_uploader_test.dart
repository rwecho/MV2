import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/errors/failures.dart';
import 'package:mv2/core/network/imgur_uploader.dart';

/// Captures the outgoing request and answers with [body] / [status].
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.body, this.status = 200, this.throwConnection});

  final String body;
  final int status;
  final bool? throwConnection;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (throwConnection ?? false) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ImgurUploader _uploader(_FakeAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  dio.httpClientAdapter = adapter;
  return ImgurUploader(dio: dio);
}

final Uint8List _bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

void main() {
  test('a successful upload resolves to the hosted link', () async {
    final adapter = _FakeAdapter(
      body: '{"success":true,"data":{"link":"https://i.imgur.com/abc.jpg"}}',
    );

    final url = await _uploader(adapter).upload(_bytes, filename: 'a.jpg');

    expect(url, 'https://i.imgur.com/abc.jpg');
    expect(adapter.lastRequest!.uri.toString(), ImgurUploader.endpoint);
  });

  test('the Authorization header uses one of the legacy Client-IDs', () async {
    final adapter = _FakeAdapter(
      body: '{"success":true,"data":{"link":"https://i.imgur.com/x.png"}}',
    );

    await _uploader(adapter).upload(_bytes);

    final header = adapter.lastRequest!.headers['Authorization'] as String;
    expect(header, startsWith('Client-ID '));
    expect(
      ImgurUploader.clientIds,
      contains(header.substring('Client-ID '.length)),
    );
  });

  test('a rejected upload surfaces Imgur\'s reason', () async {
    final adapter = _FakeAdapter(
      status: 403,
      body: '{"success":false,"data":{"error":"Rate limit exceeded"}}',
    );

    await expectLater(
      _uploader(adapter).upload(_bytes),
      throwsA(
        isA<ServerFailure>().having(
          (failure) => failure.message,
          'message',
          contains('Rate limit exceeded'),
        ),
      ),
    );
  });

  test('a transport error becomes a NetworkFailure', () async {
    final adapter = _FakeAdapter(body: '', throwConnection: true);

    await expectLater(
      _uploader(adapter).upload(_bytes),
      throwsA(isA<NetworkFailure>()),
    );
  });
}
