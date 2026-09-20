import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mv2_events.dart';
import 'mv2_telemetry.dart';

/// Firebase 启动完成的监听桩:MaterialApp watch 它,启动完成后重建一次,
/// 让 boot 阶段被丢弃的用户属性在第一次重建时补齐。
final telemetryReadyProvider = FutureProvider<bool>((ref) {
  return Mv2Telemetry.ensureFirebase();
});

/// MV2 统计门面 — 所有业务埋点的唯一出口,事件名/参数一律取自
/// [Mv2Events],禁止手写字符串。
///
/// 风格与 [Mv2Telemetry] 一致:静态方法、fire-and-forget、缺配置时静默
/// 降级为 no-op,统计永远不能拖垮业务。测试通过 [sink] 捕获事件——sink
/// 与 Firebase 就绪无关(test 环境没有 Firebase 配置),生产代码永不设置。
abstract final class Mv2Analytics {
  /// 测试注入点:非 null 时每个事件先转发到这里(已消毒的名称与参数)。
  static void Function(String event, Map<String, Object?> params)? sink;

  /// 测试注入点:非 null 时 user_id 同步先转发到这里;生产代码永不设置。
  static void Function(String? userId)? userIdSink;

  static bool get _enabled {
    if (!Mv2Telemetry.isReady) return false;
    return _analytics != null;
  }

  /// 惰性解析;Firebase 未启动/平台不支持时 `FirebaseAnalytics.instance`
  /// 会抛异常,这里转为 null。
  static FirebaseAnalytics? get _analytics {
    try {
      return FirebaseAnalytics.instance;
    } catch (error) {
      return null;
    }
  }

  static final RegExp _nameKeyPattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
  static const int _maxValueLength = 100;

  /// 页面浏览(手动 screen_view)。screenName 传 go_router 的路由模板
  /// (如 `/topic/:id`),按模式聚合而不是按具体 id 打散。
  ///
  /// 不用 `FirebaseAnalyticsObserver`:go_router 18 的根导航 observers 在
  /// 构造时拷贝进 delegate,而 Firebase 启动必然晚于 router 构建,观察者
  /// 会永远挂空。改为由 router.dart 监听 delegate 变化后调这里 — 一个
  /// 监听器同时覆盖根导航与 4 个 branch,没有挂载竞态。走 SDK 的
  /// `logScreenView` 以便 Firebase 维护"当前页面"供后续事件自动归属。
  static void logScreenView({required String screenName}) {
    final name = _sanitizeName(Mv2Events.screenView);
    if (name == null) return;
    final sink = Mv2Analytics.sink;
    if (sink != null) {
      sink(name, {'screen_name': screenName});
      return;
    }
    if (!_enabled) return;
    try {
      unawaited(
        _analytics!.logScreenView(
          screenName: screenName,
          screenClass: screenName,
        ),
      );
    } catch (error) {
      debugPrint('MV2: logScreenView failed: $error');
    }
  }

  static void _log(String event, Map<String, Object?> params) {
    final name = _sanitizeName(event);
    final Map<String, Object> clean = _sanitize(params);
    if (name == null) {
      assert(false, 'MV2: 非法事件名 "$event"(保留前缀或不符合命名约束)');
      return;
    }
    // sink 与就绪状态无关:测试环境没有 Firebase,也必须能捕获事件。
    final sink = Mv2Analytics.sink;
    if (sink != null) {
      sink(name, clean);
      return;
    }
    if (!_enabled) return;
    try {
      unawaited(_analytics!.logEvent(name: name, parameters: clean));
    } catch (error) {
      // 统计失败不影响业务;debug 下留痕。
      debugPrint('MV2: analytics logEvent failed: $error');
    }
  }

  /// Firebase 硬限制:名称/参数键 ≤40 字符且 snake_case,字符串值 ≤100。
  static String? _sanitizeName(String event) {
    if (!_nameKeyPattern.hasMatch(event)) return null;
    if (event.startsWith('firebase_') ||
        event.startsWith('google_') ||
        event.startsWith('ga_')) {
      return null;
    }
    return event;
  }

  static Map<String, Object> _sanitize(Map<String, Object?> params) {
    final clean = <String, Object>{};
    params.forEach((key, value) {
      if (!_nameKeyPattern.hasMatch(key)) return;
      if (value == null) return;
      if (value is String && value.length > _maxValueLength) {
        clean[key] = value.substring(0, _maxValueLength);
      } else {
        clean[key] = value;
      }
    });
    return clean;
  }

  // ------------------------------------------------------------------
  // 导航与浏览
  // ------------------------------------------------------------------

  static void logTabSwitch({required String tab}) =>
      _log(Mv2Events.tabSwitch, {'tab': tab});

  static void logFeedTabView({required String tab}) =>
      _log(Mv2Events.feedTabView, {'tab': tab});

  static void logFeedRefresh({required String tab}) =>
      _log(Mv2Events.feedRefresh, {'tab': tab});

  /// SWR 首帧缓存命中。[ageSec] 用于评估新鲜窗口(TTL)设置是否合理。
  static void logFeedCacheHit({required String tab, required int ageSec}) =>
      _log(Mv2Events.feedCacheHit, {'tab': tab, 'age_sec': ageSec});

  /// SWR 首帧后的后台刷新结果。[durationMs] 为网络耗时。
  static void logFeedRevalidate({
    required String tab,
    required bool ok,
    required int durationMs,
  }) => _log(Mv2Events.feedRevalidate, {
    'tab': tab,
    'result': ok ? 'ok' : 'error',
    'duration_ms': durationMs,
  });

  static void logTopicOpen({
    required int topicId,
    String source = Mv2Events.unspecified,
    required String layout,
  }) => _log(Mv2Events.topicOpen, {
    'topic_id': topicId,
    'source': source,
    'layout': layout,
  });

  static void logNodeOpen({required String nodeKey, required String source}) =>
      _log(Mv2Events.nodeOpen, {'node_key': nodeKey, 'source': source});

  static void logTopicRead({
    required int topicId,
    required int durationSec,
    required int repliesSeen,
  }) => _log(Mv2Events.topicRead, {
    'topic_id': topicId,
    'duration_sec': durationSec,
    'replies_seen': repliesSeen,
  });

  // ------------------------------------------------------------------
  // 互动
  // ------------------------------------------------------------------

  static void logTopicThank({required int topicId, required String result}) =>
      _log(Mv2Events.topicThank, {'topic_id': topicId, 'result': result});

  static void logReplyThank({
    required int topicId,
    required int floor,
    required String result,
  }) => _log(Mv2Events.replyThank, {
    'topic_id': topicId,
    'floor': floor,
    'result': result,
  });

  static void logTopicFavorite({
    required int topicId,
    required bool enabled,
    required String result,
  }) => _log(Mv2Events.topicFavorite, {
    'topic_id': topicId,
    'enabled': enabled,
    'result': result,
  });

  static void logTopicIgnore({
    required int topicId,
    required bool enabled,
    required String result,
  }) => _log(Mv2Events.topicIgnore, {
    'topic_id': topicId,
    'enabled': enabled,
    'result': result,
  });

  static void logTopicShare({required int topicId}) =>
      _log(Mv2Events.topicShare, {'topic_id': topicId});

  static void logReplyCopy({required int topicId, required int floor}) =>
      _log(Mv2Events.replyCopy, {'topic_id': topicId, 'floor': floor});

  static void logReportSubmit({required String target}) =>
      _log(Mv2Events.reportSubmit, {'target': target});

  static void logMentionTap({required bool jumped}) =>
      _log(Mv2Events.mentionTap, {'jumped': jumped});

  // ------------------------------------------------------------------
  // 回复与创作
  // ------------------------------------------------------------------

  static void logReplyOpen({required int topicId, required String source}) =>
      _log(Mv2Events.replyOpen, {'topic_id': topicId, 'source': source});

  static void logReplySubmit({
    required int topicId,
    required bool hasQuote,
    required int contentLength,
    required String result,
  }) => _log(Mv2Events.replySubmit, {
    'topic_id': topicId,
    'has_quote': hasQuote,
    'length_bucket': Mv2Events.lengthBucket(contentLength),
    'result': result,
  });

  static void logDraftAction({
    required String composer,
    required String action,
  }) => _log(Mv2Events.draftAction, {'composer': composer, 'action': action});

  static void logPublishOpen({String source = 'tab'}) =>
      _log(Mv2Events.publishOpen, {'source': source});

  static void logPublishNodeSelect({required String nodeKey}) =>
      _log(Mv2Events.publishNodeSelect, {'node_key': nodeKey});

  static void logPublishPreview() =>
      _log(Mv2Events.publishPreview, {'shown': true});

  static void logImageUpload({required String result, int? sizeBytes}) =>
      _log(Mv2Events.imageUpload, {
        'result': result,
        if (sizeBytes != null) 'size_bucket': Mv2Events.sizeBucket(sizeBytes),
      });

  static void logPublishSubmit({
    required String nodeKey,
    required bool hasImage,
    required int titleLength,
    required String result,
  }) => _log(Mv2Events.publishSubmit, {
    'node_key': nodeKey,
    'has_image': hasImage,
    'title_length_bucket': Mv2Events.lengthBucket(titleLength),
    'result': result,
  });

  // ------------------------------------------------------------------
  // 账号
  // ------------------------------------------------------------------

  static void logLoginOpen() => _log(Mv2Events.loginOpen, const {});

  static void logLoginSubmit({required String result}) =>
      _log(Mv2Events.loginSubmit, {'result': result});

  static void logTwoFactorSubmit({required String result}) =>
      _log(Mv2Events.twoFactorSubmit, {'result': result});

  static void logLogout({required String reason}) =>
      _log(Mv2Events.logout, {'reason': reason});

  static void logDailyCheckin({required String result}) =>
      _log(Mv2Events.dailyCheckin, {'result': result});

  // ------------------------------------------------------------------
  // 搜索与节点目录
  // ------------------------------------------------------------------

  static void logSearchSubmit({
    required String scope,
    required String sort,
    required int queryLength,
  }) => _log(Mv2Events.searchSubmit, {
    'scope': scope,
    'sort': sort,
    'query_length_bucket': Mv2Events.lengthBucket(queryLength),
  });

  static void logSearchResultOpen({required String type}) =>
      _log(Mv2Events.searchResultOpen, {'type': type});

  static void logRecentSearchSelect() =>
      _log(Mv2Events.recentSearchSelect, const {});

  static void logNodesFilter({required int queryLength}) => _log(
    Mv2Events.nodesFilter,
    {'query_length_bucket': Mv2Events.lengthBucket(queryLength)},
  );

  // ------------------------------------------------------------------
  // 链接 / 阅读 / 图片
  // ------------------------------------------------------------------

  static void logLinkOpen({required String mode, required bool isInternal}) =>
      _log(Mv2Events.linkOpen, {'mode': mode, 'is_internal': isInternal});

  static void logReaderOpen({required String mode}) =>
      _log(Mv2Events.readerOpen, {'mode': mode});

  static void logReaderModeChange({required String mode}) =>
      _log(Mv2Events.readerModeChange, {'mode': mode});

  static void logImageView({required String source}) =>
      _log(Mv2Events.imageView, {'source': source});

  // ------------------------------------------------------------------
  // 推送 / deeplink / 剪贴板
  // ------------------------------------------------------------------

  static void logPushOpen({required int topicId}) =>
      _log(Mv2Events.pushOpen, {'topic_id': topicId});

  static void logPushRegister({required String result}) =>
      _log(Mv2Events.pushRegister, {'result': result});

  static void logDeeplinkOpen({required String kind}) =>
      _log(Mv2Events.deeplinkOpen, {'kind': kind});

  static void logClipboardOffer({required String action}) =>
      _log(Mv2Events.clipboardOffer, {'action': action});

  // ------------------------------------------------------------------
  // 设置与数据
  // ------------------------------------------------------------------

  static void logSettingChange({required String key, required String value}) =>
      _log(Mv2Events.settingChange, {'key': key, 'value': value});

  static void logCacheClear({String result = 'success'}) =>
      _log(Mv2Events.cacheClear, {'result': result});

  static void logDataDelete({required String target}) =>
      _log(Mv2Events.dataDelete, {'target': target});

  static void logHistoryClear() => _log(Mv2Events.historyClear, const {});

  static void logReadLaterClear() => _log(Mv2Events.readLaterClear, const {});

  static void logBlockedUnblock({required int count}) =>
      _log(Mv2Events.blockedUnblock, {'count': count});

  static void logPaywallOpen({required String source}) =>
      _log(Mv2Events.paywallOpen, {'source': source});

  static void logPurchaseResult({required String result}) =>
      _log(Mv2Events.purchaseResult, {'result': result});

  static void logRestoreResult({required String result}) =>
      _log(Mv2Events.restoreResult, {'result': result});

  static void logHonorWallOpen({required String source}) =>
      _log(Mv2Events.honorWallOpen, {'source': source});

  static void logHonorJoin({required String result}) =>
      _log(Mv2Events.honorJoin, {'result': result});

  // ------------------------------------------------------------------
  // 用户属性
  // ------------------------------------------------------------------

  /// 绑定/解除分析用户 ID。登录态变化时由 app.dart 调用:登录传 member id
  /// (数字型假名标识,不用用户名——GA 视可直接识别个人的字符串为 PII),
  /// 登出传 null 解绑。绑定后所有事件都归属到该用户,Firebase 控制台的
  /// User Explorer 与 BigQuery 导出的 `user_id` 列即可回答"每个用户点了
  /// 哪些帖子、发了哪些评论"。与 [sink] 同理,userIdSink 绕过就绪门控。
  static void syncUserId({int? memberId}) {
    final userId = memberId?.toString();
    final sink = userIdSink;
    if (sink != null) {
      sink(userId);
      return;
    }
    if (!_enabled) return;
    try {
      unawaited(_analytics!.setUserId(id: userId));
    } catch (error) {
      debugPrint('MV2: setUserId failed: $error');
    }
  }

  /// 同步用户属性(boot + 设置变化时由 app.dart 调用)。参数用裸字符串,
  /// 避免 core → features 的反向依赖;调用方从枚举 `.name` 取值。
  /// 不含用户名 / member id 等 PII —— 按 user 维度归属事件走 [syncUserId]
  /// 的 user_id,用户属性只放可分群的枚举维度。
  static void syncUserProperties({
    required String colorMode,
    required String fontSize,
    required String contentWidth,
    required String linkOpenMode,
    required String pushEnabled,
    required String replySort,
    required String signedIn,
    required String layout,
  }) {
    if (!_enabled) return;
    final analytics = _analytics!;
    void set(String name, String value) {
      try {
        unawaited(analytics.setUserProperty(name: name, value: value));
      } catch (error) {
        debugPrint('MV2: setUserProperty failed: $error');
      }
    }

    set('color_mode', colorMode);
    set('font_size', fontSize);
    set('content_width', contentWidth);
    set('link_open_mode', linkOpenMode);
    set('push_enabled', pushEnabled);
    set('reply_sort', replySort);
    set('signed_in', signedIn);
    set('layout', layout);
  }
}
