# mv2 — MV2 Flutter 客户端

V2EX 第三方客户端的 Flutter 实现。设计与规范在仓库上一级：

- `../designs/` 8 张页面设计稿（视觉基线）
- `../docs/12-v2ex-api-inventory.md` 接口清单与解析要点
- `../docs/13-next-phase-plan.md` 阶段计划
- `../docs/11-design-implementation-notes.md` 设计裁量记录

## 运行

```bash
export PATH="$HOME/flutter-sdk/bin:$PATH"
flutter pub get
flutter run -d <device-id>
```

### 数据来源：真实站点

客户端**只连真实站点**（`www.v2ex.com` + `sov2ex`），没有内置样本数据。
取数失败时页面渲染标准错误态（`Mv2StateView`，带「重试」）并弹出失败提示，
不会用假数据冒充成功。

```bash
# 直连 www.v2ex.com；本机 DNS 被污染时补代理
flutter run
flutter run --dart-define=MV2_PROXY=http://127.0.0.1:7897
```

真实模式下客户端会：关闭自动重定向（靠 302 判断写操作成功）、逐请求带
`Referer`、按 350ms 间隔串行请求、把匿名页面缓存进 Drift（`/my/*`、`/notifications`、
`/mission/*`、`/settings/*` 等带账号状态的路径**永不落盘**）。

### 首页 Tab

首页顶部与 V2EX 官网 `#Tabs` 保持一致：技术 / 创意 / 好玩 / Apple / 酷工作 / 交易 /
城市 / 问与答 / 最热 / 全部 / R2 / **VXNA**（`core/data/home_tab.dart`）。11 个 `?tab=` 页
共用 `FeedParser`；`VXNA` 是 `/xna` 的站外聚合，走 `XnaParser` + `XnaItem` 外链卡片，点击
在浏览器打开。`Mv2TabStrip` 横向滚动并自动把选中项滚入视野；内容区是横向 `PageView`，
**左右滑动内容可切换 tab**，与顶部双向联动。每个 tab 有独立的 `feedProvider(tab)` 缓存与滚动
位置。选中态持久化到 `SharedPreferences`（`mv2.homeTab`），**首次默认 R2**，之后恢复上次选择。

### 通知未读 Badge

底部导航「通知」上的未读数是真实值：V2EX 在登录态首页 `#Rightbar` 的
`div.cell.flex-one-row` 通知链接里给出未读数，`AccountParser` 抓下来 → `AuthSession.unreadCount`
取数字 → `notificationUnreadProvider`（`features/notifications/...`）直接映射；登出或未知为 `0`，
不再有写死的 `3`。存储里没有该计数，所以 `AppShell` 在存储会话变为已登录时做一次
`refreshAccount()` 重新抓取；打开通知页后（服务端标记已读）会再刷新一次，Badge 随之清零。

### 滚动折叠

统一规则在 `ui/components/mv2_scroll_collapse.dart`（`mv2CollapseFromScroll`）：**向下阅读时
收起、回滚时展开**。首页收起大 header 只剩 tab 行，同时底部悬浮导航整体滑出
（`shellBarCollapsedProvider` 由 `AppShell` 消费，切换一级 Tab 时重置）；topic 页顶栏淡入
主题标题、底部悬浮回复栏滑出。横向 `PageView` 的滚动不会触发折叠。

### 下拉刷新

所有数据列表统一走 `ui/components/mv2_refreshable.dart`：`Mv2Refreshable`（accent spinner）
包住列表，`Mv2RefreshableFill` 让空态/错误态也能下拉。列表一律加
`AlwaysScrollableScrollPhysics`，内容不足一屏同样能拉。已覆盖：首页每个 tab、VXNA、节点、
节点主题流、全部节点、通知、topic 回复、用户主页、浏览历史、稍后阅读、我的节点、搜索结果。

### 错误提示

`ui/components/mv2_error_feedback.dart` 统一错误反馈：`mv2ShowError` 优先用 `Failure.message`，
`mv2ToastLoadError` 处理首次加载失败。`Mv2Refreshable` 捕获刷新失败的 future 并 toast，所以
任何列表下拉刷新失败都有提示；每个列表页用 `ref.listen` 覆盖首次加载失败；通知控制器把
`Failure` 存进 state 再 toast（它自己吞异常）；清空/删除历史、稍后阅读失败同样 toast。

注意 Riverpod 3 默认对失败的 provider **自动重试 10 次**（退避到 6.4s），期间状态是
`AsyncLoading(error:)`，`.when` 默认会一直显示骨架屏。列表页统一加 `skipLoadingOnReload: true`，
让错误态在重试期间就显示出来（避免“转圈 30 秒才报错”）。

### 评论交互

主题回复项：行内 **感谢 / 引用**；**长按**弹出 回复 / 复制 / 举报 面板（举报沿用主题的
`report@v2ex.maui` 邮件通道，预填楼层/作者/回复 ID）。

**回复行没有 👍**：V2EX 没有回复点赞/顶踩，也没有取消感谢（`combo.js` 里回复只有
`POST /thank/reply/`，单向、扣铜板、无 unlike；可切换的 `/up/topic` `/down/topic` 是主题的顶/踩），
所以设计稿的 👍 已去掉，避免死按钮，也不和感谢混为一谈。

`@某人` 的两种含义分开处理：

- **正文里的 `@某人`**（V2EX 渲染成 `@<a href="/member/x">x</a>`）表示「回复上面某条评论」→
  `Mv2RichText.onMentionTap` 拦截该链接，在本条之前找该用户最近的一条回复并引用它打开编辑器
  （找不到就开普通回复），**不跳个人主页**。
- **回复头像 / 头部 `@作者`** 进 App 内 `/member/:username`；其它 `/member/x` 也映射为站内路由
  （`Mv2RichText.internalRoute`），不会再开浏览器外链。

### once 轮换

`once` 存在 `PB3_SESSION` 里，**任何一次渲染了 `once` 输入框的页面都会签发新值并覆盖旧值**（实测连续
GET `/signin` 得到 18081 → 47098 → 75285）。所以手里缓存的 token 只要 App 又拉了别的页面（首页刷新、
回复翻页、签到…）就会失效 → 服务端 `CSRF 校验失败`。

双保险：
1. `sessionOnceProvider`（`core/data/session_once.dart`）始终保存**最新**拿到的 token —— topic detail
   重新加载、回复翻页、`/thank/*` 响应里的 `once` 都会刷新它；topic 操作与回复编辑器都用
   `sessionOnceProvider ?? 页面 once`；`signOut` 时清空。
2. 写操作被拒且 `looksLikeOnceFailure`（errors 含 `csrf`/`once`/`无效`/`刷新`，或没有 `div.problem`）时，
   **重抓当前 topic 页面拿刚签发的 token，只重试一次**（topic 操作与回复编辑器都实现了）。

### 回复 / 发布：近全屏 Modal

回复编辑器和「发布主题」都以**近全屏底部弹窗**打开，不再走整页 push：`ui/components/mv2_modal_sheet.dart`
封装 `showModalBottomSheet(isScrollControlled)`，92% 高、顶部圆角、grab handle、遮罩，关闭 X / 点遮罩 /
下拉 / 返回都可关闭，打开即 `autofocus` 弹键盘。调用入口是 `showReplyComposer(context, …)` 与
`showPublishComposer(context, …)`（`features/composer/presentation/composer_sheets.dart`）；原
`/composer`、`/publish` 两个路由已移除。键盘由页面自己的 `Scaffold.resizeToAvoidBottomInset` 顶起。

### 图片上传（Imgur）

工具栏的**图片**选相册图（`image_picker`，限宽 2400 / q90）后匿名上传到 Imgur：
`core/network/imgur_uploader.dart` 轮换旧项目共用的 9 个 Client-ID，`POST https://api.imgur.com/3/image`
（`Authorization: Client-ID …`）取 `data.link`，按光标位置插入 `![](url)`；失败按 Imgur 的 `data.error` toast。

### 表情（V2EX Polish 表情库）

`shared/emoji/mv2_emoji_library.dart` 移植 `coolpace/V2EX_Polish` 的 `src/constants.ts`：5 组 103 个
（流行 31 / 小黄脸 37 / 手势 18 / 庆祝 3 / 其他 14）。**流行**组是 B 站/小红书表情，编辑器插入
`[doge]` 这类 token、面板用 Imgur 高清图预览；提交时 `Mv2EmojiLibrary.expandForSubmit` 按 V2EX Polish
的 `transformEmoji` 把已知 token 换成低清图 URL，V2EX 才会渲染成图片（草稿保留可读 token）。
面板是工具栏上方的内联面板，点输入框自动收起。

### 从外部打开（Deep Link）

`core/deeplink/`：

- **`mv2://` scheme**：`mv2://topic/123`、`mv2://node/python`、`mv2://member/livid`
  （兼容 `mv2://t/…`、`mv2://go/…`）。iOS 在 `Info.plist` 的 `CFBundleURLTypes` 注册，Android 是
  `VIEW` intent-filter。冷启动由 `router.dart` 的 `initialLocation` 解析；平台若在路由器创建后才
  投递原始 URI，由 `redirect` 归一化（否则 go_router 报 `no routes for location: mv2://topic/123`）；
  热启动由 `Mv2DeepLinkListener` 订阅 `app_links` 的 `uriLinkStream`。
- **剪贴板识别**：`https://www.v2ex.com/t/123` 这类别人分享的链接**无法直接唤起 App**
  （Universal Links 需要在 v2ex.com 放 AASA 文件，域名不是我们的）。因此 App 回到前台（含冷启动）
  时读剪贴板，命中 V2EX 链接就弹「检测到 V2EX 链接 → 打开」，同一链接只提示一次。
  iOS 16+ 会弹系统「允许粘贴」，每次剪贴板内容变化都会再问一次——系统隐私设计，绕不开。


### 发布主题

「发布」（底部 Tab）打开近全屏 modal：抓 `GET /new[/{node}]` 的 `once` → `POST /new`
→ `302 /t/{id}`。节点来自 `/api/nodes/s2.json`（`/new` 自带选项时优先用它），正文支持
Markdown 与「预览」，草稿以 600ms 防抖写入 `SharedPreferences`（`mv2.publishDraft`，
发布成功后清除）。未登录时 `/new` 会 302 到 `/signin`，页面转为登录 CTA。
若会话不再接受缓存的 `once`（服务端把表单原样退回且不给 `Problem`），会自动重抓 `/new`
并只重试一次。fixture 模式下发布在本地校验后直接成功，便于离线走通全流程。


### SQLite 构建开关

`pubspec.yaml` 里的 `hooks.user_defines.sqlite3.source: system` 让 `package:sqlite3`
使用系统自带的 SQLite，避免从 GitHub Releases 下载预编译库。iOS/macOS 都自带
libsqlite3；**Android 发布前必须重新评估**（改回默认 bundled 或提供 `source:` 自定义构建）。

### 内购（永久买断）

设置页顶部的「MV2 永久版」进入付费墙（`/pro`），走 RevenueCat 完成
App Store / Google Play 的**非消耗型**买断；权益持久化在本地
（`mv2.pro.entitled`），换机重装走「恢复购买」。功能门控统一读
`isProProvider`（骨架阶段尚无功能依赖它）。

RevenueCat 公钥是客户端公开凭据，通过 `--dart-define` 注入，仓库不落盘：

```bash
flutter run \
  --dart-define=MV2_REVENUECAT_APPLE_KEY=appl_xxx \
  --dart-define=MV2_REVENUECAT_GOOGLE_KEY=goog_xxx
```

不注入 key 的构建（本地开发 / CI）付费墙显示「商店尚未配置」，不可购但一切正常。
商店侧需要一次性配置：

1. RevenueCat 后台建 App（iOS / Android 各一把 public key），创建 entitlement
   `pro`，把终身商品挂上去；
2. App Store Connect：非消耗型内购，商品 id `mv2.pro.lifetime`；
3. Google Play Console：托管商品，商品 id `mv2.pro.lifetime`（需先上传带计费
   权限的构建才能建档）。

实现：`lib/features/pro/`（`ProBackend` 抽象 + `RevenueCatProBackend` +
`ProController` + 付费墙），埋点 `paywall_open` / `purchase_result` /
`restore_result`。

### 荣誉墙

买断用户永久铭刻在「荣誉墙」（设置 → 荣誉墙，路由 `/honors`）。购买成功后弹窗
登记展示名（预填 V2EX 用户名，可改），Worker 用 RevenueCat secret key 核验
`pro` 权益后写入 KV；**一经铭刻不随退款移除**，展示名全局唯一（先到先得）。
购买状态本身不门控任何功能，荣誉墙入口对所有人可见。

## 质量门

```bash
flutter analyze   # 必须 0 issue
flutter test      # 解析器 / 网络层 / 缓存 / 主题 token 回归
```

## 目录

```
lib/
├── app/            app.dart（主题 + 路由）· router.dart
├── core/
│   ├── data/       v2ex_api.dart（远端 + fixture 两种实现）· providers
│   ├── errors/     Failure 模型
│   ├── network/    Dio 客户端 · cookie 存储 · 端点与中文常量
│   ├── parser/     选择器与 HTML 解析器（Feed / Topic / Node / Publish）
│   └── storage/    Drift 缓存库 + 匿名白名单策略
├── design_system/  tokens / theme / effects
├── ui/             primitives · components · states
├── features/       按功能分层（data · domain · application · presentation）
└── shared/         models · mock（未接线的页面仍在用） · format（含 Markdown 预览）
```
