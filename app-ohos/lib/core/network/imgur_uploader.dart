import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/failures.dart';

/// Anonymous Imgur upload, used by both composers to host inserted images.
///
/// V2EX has no upload endpoint of its own — the web editor and the legacy
/// .NET/React client post the image to Imgur and paste the returned link
/// (`docs/12` §8). That client shipped a pool of anonymous Client-IDs and
/// picked one at random to spread Imgur's per-id rate limit; the same pool is
/// reused here.
///
/// `POST https://api.imgur.com/3/image` with `Authorization: Client-ID {id}`
/// answers `{success: true, data: {link: "https://i.imgur.com/…"}}`; a
/// rejection carries `data.error`.
class ImgurUploader {
  ImgurUploader({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              // Imgur answers 4xx with a JSON body we parse ourselves.
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  static const String endpoint = 'https://api.imgur.com/3/image';

  /// Legacy anonymous Client-ID pool, rotating to spread the rate limit.
  static const List<String> clientIds = <String>[
    '3107b9ef8b316f3',
    '442b04f26eefc8a',
    '59cfebe717c09e4',
    '60605aad4a62882',
    '6c65ab1d3f5452a',
    '83e123737849aa9',
    '9311f6be1c10160',
    'c4a4a563f698595',
    '81be04b9e4a08ce',
  ];

  final Dio _dio;
  final Random _random = Random();

  String _clientId() => clientIds[_random.nextInt(clientIds.length)];

  /// Uploads [bytes] and resolves to the hosted image URL.
  ///
  /// Throws a [Failure] with a user-facing message on rejection or transport
  /// error so callers can toast it directly.
  Future<String> upload(Uint8List bytes, {String? filename}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        endpoint,
        data: FormData.fromMap(<String, dynamic>{
          'image': MultipartFile.fromBytes(
            bytes,
            filename: filename ?? 'mv2-image',
          ),
          'type': 'file',
        }),
        options: Options(
          headers: <String, String>{'Authorization': 'Client-ID ${_clientId()}'},
        ),
      );

      final data = response.data;
      final success = data?['success'];
      if (success == true) {
        final link = (data?['data'] as Map?)?['link']?.toString();
        if (link != null && link.isNotEmpty) return link;
      }
      throw ServerFailure(
        message: _errorMessage(data) ?? '图片上传失败，请稍后重试。',
      );
    } on DioException catch (error, stackTrace) {
      if (error.response?.data is Map) {
        final message = _errorMessage(error.response!.data as Map);
        throw ServerFailure(
          message: message ?? '图片上传失败，请稍后重试。',
          cause: error,
          stackTrace: stackTrace,
        );
      }
      throw const NetworkFailure(message: '图片上传失败，请检查网络后重试。');
    }
  }

  /// Imgur nests the reason in `data.error` (string or `{message}`).
  static String? _errorMessage(Map? body) {
    if (body == null) return null;
    final data = body['data'];
    final raw = data is Map ? (data['error'] ?? data['message']) : data;
    final value = (raw ?? body['error'] ?? body['message'])?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return '图片上传失败：$value';
  }
}

final imgurUploaderProvider = Provider<ImgurUploader>((ref) => ImgurUploader());
