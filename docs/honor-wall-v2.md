# 荣誉墙 v2：购买与公开署名独立

## 用户规则

- 游客可购买、恢复 Pro，不需要 V2EX 账号。
- Pro 在当前安装中与 V2EX 账号切换独立。
- 登记、改名、隐藏均为主动操作。失败保留输入，不影响 Pro。
- 同一原始 App Store 非消耗型交易只有一条记录；改名、恢复和重新展示保留首次登记时间。
- 隐藏只从公开列表移除，不删除购买记录，也不取消 Pro。

## 核验与存储

`MV2NativeBridge.proPurchaseProof` 返回 StoreKit 已验证的 `mv2.pro.lifetime` 当前权益 JWS。
客户端通过 HTTPS 将证明和当前 RevenueCat 客户 ID 发送到 Worker；不得记录这些凭据。
Worker 使用 Apple 官方 App Store Server Library、Apple Root CA G3 核验签名链、应用和环境，
再检查商品类型、撤销状态、原始交易 ID。RevenueCat 必须同时返回当前 Pro 权益及匹配的
`non_subscriptions["mv2.pro.lifetime"].store_transaction_id`，防止使用其他购买者的 RC ID 或已退款的旧证明。

Production / Sandbox 分别使用两个 Durable Object；Sandbox 名单不会出现在正式公开列表。
本地 Xcode StoreKit 证明不由 Apple 根证书签发，服务端拒绝此类证明。

一个 Durable Object 在存储事务中完成交易去重、名称占用、改名及隐藏。
首次访问时从 KV 的 `honor:index` 导入旧名单，原 KV 数据保留。
通过购买证明及 RevenueCat 记录核验后，当前 ID 或 original_app_user_id 对应的旧记录迁移到原始交易键。
若历史条目使用了不再返回的其他别名，不进行猜测合并，需管理端人工核实迁移。

公开列表不返回购买 ID、RC ID 或 JWS。旧 `GET /honors` 转发新公开列表。
旧 `POST /honors/join` 返回 426：仅提供 RC ID 的旧客户端不能继续写入。

## 发布顺序与验证门槛

1. 保留现有 `REVENUECAT_SECRET_KEY` Worker secret。核对其能访问正式和 Sandbox 客户。
2. 使用 `cloudflare/wrangler.toml` 的 `HONOR_REGISTRY` 绑定和 `honor-registry-v1` SQLite Durable Object 迁移部署服务端。
3. 查询公开列表并确认旧名单、顺序未丢失；先在 Sandbox 完成购买、登记、重装恢复、改名、隐藏测试。
4. 再发布含新接口和 Swift bridge 的 iOS 应用。新应用与旧服务端不兼容，必须先部署服务端。

Android 通过 BillingClient 只读查询已购买的非消耗型商品 token；支付本身仍由 RevenueCat 发起。
Worker 使用 `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secret 获取 androidpublisher 范围的 OAuth token，
调用固定包名和商品的 Google Play Developer API，验证已购买、未消耗状态并与 RC 订单匹配。
购买 token 的 SHA-256 作为稳定登记键，token 不出现在公开名单中；许可测试订单进入 Sandbox 名单。
部署前需给 Worker 配置具有该应用购买查询权限的 Google Play 服务账号；此凭据不能写入仓库。
旧客户端仍可浏览名单和购买 Pro，但登记需要升级（旧登记接口返回 426）。

已完成的本地验证不代表真实购买联调成功。测试中的正向交易编排使用替身验证器；
真实签名验证仅做了拒绝无效证明的测试，仍需真实 Sandbox JWS 与 RC 返回结构端到端验证。
