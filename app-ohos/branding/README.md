# MV2 品牌资源

这里的 logo 不是新设计的：它是**已发布 MV2 应用**的品牌标识，从 .NET MAUI 旧工程
（`~/workspace/V2ex.Maui2`）的 `src/V2ex.Maui2.App/Resources/AppIcon/` 合并而来——
`appicon.svg`（白色底）+ `appiconfg.svg`（渐变 V + 粉色圆点）。本次 Flutter 重写是**升级**，
必须保持与旧版一致的品牌与包标识，而不是注册一个新的软件。

| 文件 | 用途 |
|---|---|
| `mv2_logo.svg` | 完整图标（白底 + V），用于 iOS / macOS / web / Android 传统图标 |
| `mv2_logo_mark.svg` | 透明底 V，用于启动图；渲染 Android 自适应前景时按 1.2× 取景 |
| `generate_icons.py` | 把上面两个 SVG 渲染成各平台所有尺寸的 PNG |

## 重新生成

```bash
pip3 install cairosvg pillow     # 一次性
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

iOS / macOS 图标输出会**去掉 alpha 通道**（App Store 要求，白底本身不透明，因此无损）；
启动图保留透明，从而在 iOS 白底与 Android 深色模式下都成立。

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
