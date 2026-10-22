import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/push/push_service.dart';

class HonorEntry {
  const HonorEntry({
    required this.name,
    required this.joinedAt,
    this.hidden = false,
  });
  final String name;
  final DateTime joinedAt;
  final bool hidden;
  static HonorEntry fromMap(Object? raw) {
    final map = Map<String, Object?>.from(raw as Map);
    return HonorEntry(
      name: map['name']! as String,
      joinedAt: DateTime.fromMillisecondsSinceEpoch(map['joinedAt']! as int),
      hidden: map['hidden'] == true,
    );
  }
}

enum HonorJoinResult { joined, already, nameTaken, notEntitled, error }

/// Community login and public RevenueCat IDs are never used to authenticate
/// wall changes. Native stores supply an Apple-signed transaction or Play token.
class HonorsApi {
  HonorsApi({Dio? dio, String? baseUrl, Future<String?> Function()? proof})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          ),
      _baseUrl = baseUrl ?? Mv2PushService.workerBaseUrl,
      _proof = proof ?? _storeProof;
  final Dio _dio;
  final String _baseUrl;
  final Future<String?> Function() _proof;

  static Future<String?> _storeProof() async {
    try {
      return await const MethodChannel('mv2/native')
          .invokeMethod<String>('proPurchaseProof');
    } on MissingPluginException {
      return null;
    }
  }

  Future<Map<String, Object?>> _credentials() async {
    final proof = await _proof();
    if (proof == null || proof.isEmpty) {
      throw const HonorProofUnavailable();
    }
    return {'proof': proof, 'rcUserId': await Purchases.appUserID};
  }

  Future<List<HonorEntry>> fetch() async {
    String? proof;
    try {
      proof = await _proof();
    } on Exception {
      /* Public wall remains available. */
    }
    final res = await _dio.post<Map<String, Object?>>(
      '$_baseUrl/honors/v2/list',
      data: {'proof': proof},
    );
    final honors = res.data?['honors'];
    if (honors is! List) throw const FormatException('Invalid honor list');
    return honors.map(HonorEntry.fromMap).toList(growable: false);
  }

  Future<HonorEntry?> status() async {
    final res = await _dio.post<Map<String, Object?>>(
      '$_baseUrl/honors/v2/status',
      data: await _credentials(),
    );
    final entry = res.data?['entry'];
    return entry == null ? null : HonorEntry.fromMap(entry);
  }

  Future<void> hide() async {
    await _dio.post<Map<String, Object?>>(
      '$_baseUrl/honors/v2/hide',
      data: await _credentials(),
    );
  }

  Future<HonorJoinResult> join({required String name}) async {
    try {
      await _dio.post<Map<String, Object?>>(
        '$_baseUrl/honors/v2/join',
        data: {...await _credentials(), 'name': name},
      );
      return HonorJoinResult.joined;
    } on HonorProofUnavailable {
      return HonorJoinResult.notEntitled;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) return HonorJoinResult.notEntitled;
      if (e.response?.statusCode == 409 &&
          e.response?.data?['error'] == 'name_taken') {
        return HonorJoinResult.nameTaken;
      }
      return HonorJoinResult.error;
    } on Exception {
      return HonorJoinResult.error;
    }
  }
}

class HonorProofUnavailable implements Exception {
  const HonorProofUnavailable();
}
