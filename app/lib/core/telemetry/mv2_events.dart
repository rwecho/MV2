/// MV2 埋点事件目录 — 全应用唯一的「事件名 + 参数」事实源。
///
/// 规则:
/// - 事件名与参数键均为 snake_case,≤40 字符(Firebase 硬限制),不带
///   `firebase_` / `google_` / `ga_` 保留前缀;
/// - 参数只允许 id / slug / 枚举名 / bucket,**禁止**用户名、搜索词原文、
///   标题、外链 URL、剪贴板内容等 PII;
/// - 发送统一经 [Mv2Analytics],调用方不要直接 `FirebaseAnalytics.logEvent`。
abstract final class Mv2Events {
  /// `source` / `entry` 类参数的缺省值:调用点确实无从判断来源时使用。
  static const String unspecified = 'unspecified';

  // ------------------------------------------------------------------
  // 导航与浏览
  // ------------------------------------------------------------------

  /// 页面浏览(手动 screen_view,经 FirebaseAnalytics.logScreenView)。
  /// screenName 用 go_router 的路由模板(如 `/topic/:id`),避免按 id 打散。
  static const String screenView = 'screen_view';

  /// 主壳底部标签切换(发布按钮除外,它记 publish_open)。
  /// `tab`: feed|nodes|notifications|profile
  static const String tabSwitch = 'tab_switch';

  /// 首页 12 个子 feed 的浏览(点标签与横滑共用同一咽喉点)。
  /// `tab`: HomeTab.slug,如 tech / hot / vxna
  static const String feedTabView = 'feed_tab_view';

  /// 首页 feed 下拉刷新(仅手势触发,无按钮入口)。
  /// `tab`: HomeTab.slug
  static const String feedRefresh = 'feed_refresh';

  /// 打开主题详情。归因核心事件:`source` 记录入口
  /// (feed|search|node|member|history|read_later|my_list|notifications|
  ///  publish|push|deeplink|clipboard),`layout`: phone|tablet。
  static const String topicOpen = 'topic_open';

  /// 从目录/搜索/主题卡片打开节点主题列表(正文内链由 link_open 覆盖,不在此重复)。
  /// `node_key`: 节点 slug;`source`: recent|nodes_hot|nodes_all|search|
  ///  topic_card|topic_detail
  static const String nodeOpen = 'node_open';

  /// 主题阅读时长结算(进入详情计时,离开页面 dispose 上报)。
  /// `duration_sec`: 整数秒;`replies_seen`: 离开时已加载的回复数
  static const String topicRead = 'topic_read';

  // ------------------------------------------------------------------
  // 互动
  // ------------------------------------------------------------------

  /// 感谢主题。`result`: success|failed|auth_required
  static const String topicThank = 'topic_thank';

  /// 感谢回复。`floor`: 楼层号;`result`: success|failed|auth_required
  static const String replyThank = 'reply_thank';

  /// 收藏/取消收藏主题。`enabled`: 目标状态;`result`: success|failed
  static const String topicFavorite = 'topic_favorite';

  /// 忽略/取消忽略主题。`enabled`: 目标状态;`result`: success|failed
  static const String topicIgnore = 'topic_ignore';

  /// 分享主题(share_plus 不回调用户选的渠道,故无 channel 参数)。
  static const String topicShare = 'topic_share';

  /// 长按回复复制内容。`floor`: 楼层号
  static const String replyCopy = 'reply_copy';

  /// 举报(邮件打开即算)。`target`: topic|reply
  static const String reportSubmit = 'report_submit';

  /// 点 @提及。`jumped`: 是否跳到了对应楼层(false = 打开用户主页)
  static const String mentionTap = 'mention_tap';

  // ------------------------------------------------------------------
  // 回复与创作
  // ------------------------------------------------------------------

  /// 打开回复编辑器。`source`: bar(底部回复栏)|quote(引用)|long_press
  static const String replyOpen = 'reply_open';

  /// 提交回复。`has_quote`: 是否携带引用;`length_bucket`: 内容长度分桶;
  /// `result`: success|failed|rate_limited|auth_required
  static const String replySubmit = 'reply_submit';

  /// 草稿生命周期。`composer`: reply|publish;
  /// `action`: saved|restored|cleared(saved 仅在内容非空时记)
  static const String draftAction = 'draft_action';

  /// 打开发帖编辑器。`source`: tab(发布按钮)|quick_action(iOS 快捷方式)
  static const String publishOpen = 'publish_open';

  /// 发帖时选择节点。`node_key`: 节点 slug
  static const String publishNodeSelect = 'publish_node_select';

  /// 发帖预览(仅开启预览时记)。
  static const String publishPreview = 'publish_preview';

  /// 编辑器插图上传到 Imgur(两个 composer 共用同一按钮)。
  /// `size_bucket`: 图片体积分桶;`result`: success|failed
  static const String imageUpload = 'image_upload';

  /// 提交新主题(控制器终态,token 重试路径只记一次)。
  /// `node_key` / `has_image` / `title_length_bucket` / `result`: success|failed
  static const String publishSubmit = 'publish_submit';

  // ------------------------------------------------------------------
  // 账号
  // ------------------------------------------------------------------

  /// 进入登录页(单点在 initState,所有入口共用)。
  static const String loginOpen = 'login_open';

  /// 提交登录表单。`result`: success|failed|needs_2fa|rate_limited
  static const String loginSubmit = 'login_submit';

  /// 提交两步验证码。`result`: success|failed
  static const String twoFactorSubmit = 'two_factor_submit';

  /// 登出(咽喉点在控制器,覆盖手动退出与会话过期)。
  /// `reason`: user_initiated|session_expired
  static const String logout = 'logout';

  /// 每日签到。`result`: success|already|failed
  static const String dailyCheckin = 'daily_checkin';

  // ------------------------------------------------------------------
  // 搜索与节点目录
  // ------------------------------------------------------------------

  /// 显式提交搜索(防抖自动补发不记)。**绝不记录查询词原文**。
  /// `scope`: topic|member|node;`sort`: relevance|created;
  /// `query_length_bucket`: 查询词长度分桶
  static const String searchSubmit = 'search_submit';

  /// 点搜索结果。`type`: topic|member|node
  static const String searchResultOpen = 'search_result_open';

  /// 选用一条历史搜索词。
  static const String recentSearchSelect = 'recent_search_select';

  /// 全部节点页筛选(防抖内、非空才记)。
  /// `query_length_bucket`: 筛选词长度分桶
  static const String nodesFilter = 'nodes_filter';

  // ------------------------------------------------------------------
  // 链接 / 阅读 / 图片
  // ------------------------------------------------------------------

  /// 点击正文/回复里的链接(全应用唯一咽喉点)。
  /// `mode`: internal|reader|original|browser;`is_internal`: 站内路由
  static const String linkOpen = 'link_open';

  /// 打开内置阅读器。`mode`: reader|original(初始模式)
  static const String readerOpen = 'reader_open';

  /// 阅读器内切换渲染模式。`mode`: reader|original
  static const String readerModeChange = 'reader_mode_change';

  /// 点开内容图片查看器。`source`: content
  static const String imageView = 'image_view';

  // ------------------------------------------------------------------
  // 推送 / deeplink / 剪贴板 归因
  // ------------------------------------------------------------------

  /// 点系统推送通知拉起应用。`topic_id`: 通知关联主题(可空则不发)
  static const String pushOpen = 'push_open';

  /// 推送注册结果(只记枚举,不记 token / feedUrl)。
  /// `result`: registered|unchanged|disabled|unavailable|permission_denied|
  ///           no_feed_url|no_token|failed
  static const String pushRegister = 'push_register';

  /// 外部 deeplink 打开应用。`kind`: mv2(mv2://)|web(https v2ex 链接)
  static const String deeplinkOpen = 'deeplink_open';

  /// 剪贴板 V2EX 链接提示。`action`: shown(弹出)|accepted(点了打开)
  static const String clipboardOffer = 'clipboard_offer';

  // ------------------------------------------------------------------
  // 内购（永久买断）
  // ------------------------------------------------------------------

  /// 打开付费墙。`source`: settings|feature_gate(未来的功能门控入口)
  static const String paywallOpen = 'paywall_open';

  /// 发起购买永久版。`result`: success|cancelled|pending|error|unconfigured
  static const String purchaseResult = 'purchase_result';

  /// 恢复购买。`result`: success(恢复到权益)|no_entitlement|error
  static const String restoreResult = 'restore_result';

  /// 打开赞助榜。`source`: profile|settings|paywall|feature_gate
  static const String honorWallOpen = 'honor_wall_open';

  /// 铭刻赞助榜。`result`: joined|already|name_taken|not_entitled|error
  static const String honorJoin = 'honor_join';

  // ------------------------------------------------------------------
  // 设置与数据
  // ------------------------------------------------------------------

  /// 任一设置项变更(通用 key/value,不拆分事件)。
  /// `key`: color_mode|font_size|content_width|link_open_mode|
  ///        auto_collapse|haptics|push_enabled|reply_sort;
  /// `value`: 枚举名或 'true'/'false'(split_ratio 拖动不记)
  static const String settingChange = 'setting_change';

  /// 清除 HTTP 缓存。`result`: success
  static const String cacheClear = 'cache_clear';

  /// 请求删除数据(跳外部浏览器前记)。`target`: deletion_page
  static const String dataDelete = 'data_delete';

  /// 清空浏览历史。
  static const String historyClear = 'history_clear';

  /// 清空稍后读。
  static const String readLaterClear = 'read_later_clear';

  /// 解除屏蔽。`count`: 本次解除的用户数(单个=1,清空=n)
  static const String blockedUnblock = 'blocked_unblock';

  /// 事件名 → 参数键清单,供单元测试校验命名约束(勿在业务代码使用)。
  static const Map<String, List<String>> catalog = {
    screenView: [],
    tabSwitch: ['tab'],
    feedTabView: ['tab'],
    feedRefresh: ['tab'],
    topicOpen: ['topic_id', 'source', 'layout'],
    nodeOpen: ['node_key', 'source'],
    topicRead: ['topic_id', 'duration_sec', 'replies_seen'],
    topicThank: ['topic_id', 'result'],
    replyThank: ['topic_id', 'floor', 'result'],
    topicFavorite: ['topic_id', 'enabled', 'result'],
    topicIgnore: ['topic_id', 'enabled', 'result'],
    topicShare: ['topic_id'],
    replyCopy: ['topic_id', 'floor'],
    reportSubmit: ['target'],
    mentionTap: ['jumped'],
    replyOpen: ['topic_id', 'source'],
    replySubmit: ['topic_id', 'has_quote', 'length_bucket', 'result'],
    draftAction: ['composer', 'action'],
    publishOpen: ['source'],
    publishNodeSelect: ['node_key'],
    publishPreview: ['shown'],
    imageUpload: ['result', 'size_bucket'],
    publishSubmit: ['node_key', 'has_image', 'title_length_bucket', 'result'],
    loginOpen: [],
    loginSubmit: ['result'],
    twoFactorSubmit: ['result'],
    logout: ['reason'],
    dailyCheckin: ['result'],
    searchSubmit: ['scope', 'sort', 'query_length_bucket'],
    searchResultOpen: ['type'],
    recentSearchSelect: [],
    nodesFilter: ['query_length_bucket'],
    linkOpen: ['mode', 'is_internal'],
    readerOpen: ['mode'],
    readerModeChange: ['mode'],
    imageView: ['source'],
    pushOpen: ['topic_id'],
    pushRegister: ['result'],
    deeplinkOpen: ['kind'],
    clipboardOffer: ['action'],
    settingChange: ['key', 'value'],
    cacheClear: ['result'],
    dataDelete: ['target'],
    historyClear: [],
    readLaterClear: [],
    blockedUnblock: ['count'],
    paywallOpen: ['source'],
    purchaseResult: ['result'],
    restoreResult: ['result'],
    honorWallOpen: ['source'],
    honorJoin: ['result'],
  };

  /// 文本长度分桶(回复/标题/搜索词),避免记录原文。
  static String lengthBucket(int length) {
    if (length <= 0) return '0';
    if (length < 20) return '1-19';
    if (length < 100) return '20-99';
    if (length < 500) return '100-499';
    return '500+';
  }

  /// 字节体积分桶(上传图片)。
  static String sizeBucket(int bytes) {
    const kb = 1024;
    if (bytes < 100 * kb) return '<100kb';
    if (bytes < 1024 * kb) return '100kb-1mb';
    if (bytes < 5 * 1024 * kb) return '1mb-5mb';
    return '>5mb';
  }
}
