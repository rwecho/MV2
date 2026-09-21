import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/core/network/v2ex_endpoints.dart';
import 'package:mv2/shared/models/login_form.dart';

/// Captures the GET/POST pair `loginWithSolana` issues and answers with a
/// canned `/auth/solana` response, so the result mapping (success / unbound /
/// rejection) can be asserted offline against the real `RemoteV2exApi`.
class _FakeClient extends Mv2HttpClient {
  _FakeClient(this.status, this.body) : super(Dio(), CookieJar());

  final int status;
  final String body;

  final List<String> gets = <String>[];
  final List<({String path, Map<String, dynamic> data})> posts =
      <({String path, Map<String, dynamic> data})>[];

  @override
  Future<HttpResult> get(
    String path, {
    Map<String, dynamic>? query,
    String? referer,
    String? baseUrl,
    String? userAgent,
    PacePriority priority = PacePriority.userRead,
  }) async {
    gets.add(path);
    return HttpResult(
      statusCode: 200,
      body: '<html>/signin fixture</html>',
      headers: const <String, List<String>>{},
    );
  }

  @override
  Future<HttpResult> postJson(
    String path, {
    required Map<String, dynamic> data,
    String? referer,
    bool toleratesHttpErrors = false,
  }) async {
    posts.add((path: path, data: data));
    return HttpResult(
      statusCode: status,
      body: body,
      headers: const <String, List<String>>{},
    );
  }
}

void main() {
  final signature = 'ab' * 64;  const publicKey = '3r6oHLZQpB6WVnxgkAEyLTidBtkPxR8UriWy6iJUZCGE';
  const message = 'Sign in to V2EX: 1758417000';

  Future<({_FakeClient client, V2SolanaLoginResult result})> submit(
    int status,
    String body,
  ) async {
    final client = _FakeClient(status, body);
    final api = RemoteV2exApi(client);
    final result = await api.loginWithSolana(
      publicKey: publicKey,
      signature: signature,
      message: message,
    );
    return (client: client, result: result);
  }

  test('a 2xx answer reports success', () async {
    final (:client, :result) = await submit(200, '');
    expect(result.success, isTrue);
    expect(result.walletLinked, isTrue);
    expect(result.serverError, isNull);
    expect(client.posts.single.data, <String, dynamic>{
      'signature': signature,
      'message': message,
      'public_key': publicKey,
    });
  });

  test('visits /signin first to mirror the browser same-origin fetch', () async {
    final (:client, result: _) = await submit(200, '');
    expect(client.gets, contains(V2exEndpoints.signInWithNext));
    expect(client.posts.single.path, V2exEndpoints.authSolana);
  });

  test('404 "Address is not linked to any member" is structured, not an error',
      () async {
    final (client: _, :result) = await submit(
      404,
      '{"error": "Address is not linked to any member"}',
    );
    expect(result.success, isFalse);
    expect(result.walletLinked, isFalse);
  });

  test('a stale timestamp surfaces the guidance, not raw English', () async {
    final (client: _, :result) = await submit(
      400,
      '{"error": "Message timestamp expired"}',
    );
    expect(result.success, isFalse);
    expect(result.walletLinked, isTrue);
    expect(result.serverError, contains('过期'));
  });

  test('an invalid signature points at the private key', () async {
    final (client: _, :result) = await submit(401, '{"error": "Invalid signature"}');
    expect(result.serverError, contains('私钥'));
  });

  test('a non-JSON rejection falls back to a generic message', () async {
    final (client: _, :result) = await submit(500, '<html>boom</html>');
    expect(result.success, isFalse);
    expect(result.serverError, contains('500'));
  });
}
