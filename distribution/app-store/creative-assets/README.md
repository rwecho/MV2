# MV2 App Store creative assets

这组素材按 Apple 当前的 Product Page Header / Search Results 规范生成：

| placement | 文件 | 尺寸 | 比例 |
|---|---|---:|---:|
| Product page header | `mv2-product-page-header-21x9-3840x1646.png` | 3840 × 1646 | 21:9 |
| Search results | `mv2-search-results-3x2-2880x1920.png` | 2880 × 1920 | 3:2 |

生成命令：

```bash
python3 distribution/app-store/creative-assets/generate_creative_assets.py
```

素材使用 `docs/images/1.png` 和 `docs/images/2.png` 中的真实产品界面，外围文案只表达 MV2 的核心体验：阅读主题、搜索节点、参与讨论。PNG 导出为 RGB，无 alpha/transparency。提交前仍需在 App Store Connect 的 Preview 中查看 iPhone、iPad、横竖屏和本地化裁切效果；当前文件是可复核的 draft，不代表已经提交或通过审核。
