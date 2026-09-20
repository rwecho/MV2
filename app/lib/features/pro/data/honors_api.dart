import 'package:dio/dio.dart';

import '../../../core/push/push_service.dart';

/// 赞助榜上的一条铭刻。
class HonorEntry {
  const HonorEntry({required this.name, required this.joinedAt});

  final String name;
  final DateTime joinedAt;

  static HonorEntry fromMap(Object? raw) {
    final map = Map<String, Object?>.from(raw as Map);
    return HonorEntry(
      name: map['name']! as String,
      joinedAt: DateTime.fromMillisecondsSinceEpoch(map['joinedAt']! as int),
    );
  }
}

/// 登记结局（与服务端 `/honors/join` 的应答一一对应）。
enum HonorJoinResult {
  /// 登记成功，名字已永久铭刻。
  joined,

  /// 这一份买断之前已经登记过（重装/换机再来）。
  already,

  /// 展示名已被别的买断占用。
  nameTaken,

  /// RevenueCat 核实后没有有效 `pro` 权益。
  notEntitled,

  /// 网络/服务端错误。
  error,
}

/// 赞助榜 API —— 跑在推送同一个 Cloudflare Worker 上。
///
/// Worker 端用 RevenueCat secret key 核验购买后才写入，所以客户端不需要
/// （也不应该）自证"我买过"。
class HonorsApi {
  HonorsApi({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          ),
      _baseUrl = baseUrl ?? Mv2PushService.workerBaseUrl;

  final Dio _dio;
  final String _baseUrl;

  /// 整面墙，按铭刻时间升序（最早的支持者排最前）。
  Future<List<HonorEntry>> fetch() async {
    final res = await _dio.get<Map<String, Object?>>('$_baseUrl/honors');
    final honors = res.data?['honors'];
    if (honors is! List) return const <HonorEntry>[];
    return honors.map(HonorEntry.fromMap).toList(growable: false);
  }

  /// 以 [rcUserId]（RevenueCat app user id）登记 [name]。
  Future<HonorJoinResult> join({
    required String name,
    required String rcUserId,
  }) async {
    try {
      final res = await _dio.post<Map<String, Object?>>(
        '$_baseUrl/honors/join',
        data: <String, Object?>{'name': name, 'rcUserId': rcUserId},
      );
      final already = res.data?['already'] == true;
      return already ? HonorJoinResult.already : HonorJoinResult.joined;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 403) return HonorJoinResult.notEntitled;
      if (status == 409) {
        final error = e.response?.data?['error'];
        return error == 'name_taken'
            ? HonorJoinResult.nameTaken
            : HonorJoinResult.error;
      }
      return HonorJoinResult.error;
    } on Exception {
      return HonorJoinResult.error;
    }
  }
}
