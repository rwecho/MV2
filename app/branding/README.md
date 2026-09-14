# MV2 品牌资源

## 图标（2026-09-14 起为新版）

品牌标识由**产品负责人亲手重绘**：`source/symmetric_red_blue_v_exact.svg`——
两粒对称的胶囊药丸构成 V（左红 `#C90522`、右蓝 `#0953A3`，各 190×700、圆角 95、
倾角 ±28°），即"黑客帝国的红药丸与蓝药丸"。这是取代旧版渐变 V 的**新品牌标识**。

| 文件 | 用途 |
|---|---|
| `source/symmetric_red_blue_v_exact.svg` | **唯一几何来源**（产品负责人的原始文件，保持只读） |
| `generate_icons.py` | 从来源**组合**出所有变体并渲染成各平台 PNG |

> `mv2_logo.svg` / `mv2_logo_mark.svg` 由脚本生成，请勿手改；旧版 MAUI 的
> 渐变 V 已被此设计取代。

生成脚本不复制几何——它在内存里组合：白底、透明、以及为适配图标安全圆做的缩放。

## 重新生成

```bash
pip3 install cairosvg pillow numpy    # 一次性
python3 app/branding/generate_icons.py
```

脚本会覆盖以下位置：

- `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`（尺寸由文件名解析）
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage*.png`（启动图，透明底）
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png`
- `android/app/src/main/res/mipmap-*/ic_launcher.png`（传统图标，48dp 基准）
- `android/app/src/main/res/mipmap-*/ic_launcher_foreground.png`（自适应前景，108dp 基准）
- `android/app/src/main/res/mipmap-*/launch_image.png`（启动图，96dp 基准）
- `web/favicon.png`、`web/icons/Icon-*.png`
- `branding/mv2_logo.svg`（白底完整 logo，供直接查看）

iOS / macOS 图标输出会**去掉 alpha 通道**（App Store 要求，白底本身不透明，因此无损）；
启动图保留透明，从而在 iOS 白底与 Android 深色模式下都成立。

**自适应前景缩放是脚本实测计算的**：Android 启动器遮罩最小是画布中央 2/3 的圆，
脚本会量出墨水实际半径并自动缩放，因此重画 mark 后不会被圆遮罩切掉。

## 旧版一致性

包标识、显示名与 Firebase 项目**均沿用已发布 MV2**（详见下方两节），因此本次仍是
**升级**而非注册新软件；图标视觉更新是产品负责人的明确决定。


## 与已发布 App 的身份一致性

旧版（MAUI）发布配置 `.github/workflows/publish.yml` 使用：

- Android `packageName` / iOS `bundle-id`：**`tech.zb.v2ex.maui.app`**
- `ApplicationTitle`：**MV2**

Flutter 工程已对齐为该 bundle id 与显示名，从而作为**升级**覆盖安装；Firebase
（`GoogleService-Info.plist` / `google-services.json`）也绑定同一 id，推送无需重建项目。

## 版本号

`pubspec.yaml` 的 `version:` 也必须领先旧版，否则两个商店都按降级拒收。旧版 CI
（`.github/workflows/publish.yml`）的规则是：

```
CFBundleShortVersionString / versionName = git tag（去掉 v），例如 1.2.34
CFBundleVersion / versionCode           = printf("%d%03d%03d", MAJOR, MINOR, PATCH) + GITHUB_RUN_NUMBER
                                          例如 1.2.34 → "1002034" + run number
```

因此 Flutter 侧取 `1.2.35+1002035000`（1.2.35 的 base `1002035` + `000`）。**上传前请用
Play Console / App Store Connect 上的实际 versionCode 复核一次**：如果旧 run number 曾达到
4 位以上，就把 `+N` 再调大（Play 的 versionCode 上限是 2,100,000,000）。
