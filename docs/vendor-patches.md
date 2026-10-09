# Vendored adaptive_platform_ui（1.0.2 + 本地补丁）

`app/pubspec.yaml` 通过 `dependency_overrides` 把 `adaptive_platform_ui` 指向
`vendor/adaptive_platform_ui`（上游 1.0.2 的拷贝，已删除 `img/`、`example/`）。

## 为什么 vendor

Duo 展开态（双栏）下，点开 topic 会让右栏详情页成为 chrome 的 owner，但它的
`enclosingRoutes` 不含 shell route（它就在 shell route 里、根 Navigator 下），
`ToolbarRegistry.tabBarOwnerFor` 匹配失败，tab bar 从此消失。上游 1.0.2
（2026-10-08）尚未修复此问题。

## 补丁内容

`lib/src/toolbar/toolbar_registry.dart` — `tabBarOwnerFor`：

```dart
(entry.route == candidate.route ||
    entry.enclosingRoutes.contains(candidate.route))
```

新增第一个分支：与 tabs 宿主同 route 的页面（shell 内建的详情窗格）视为
"在 tab 布局内"，tab bar 保持可见；被 push 的全屏页面语义不变（照旧隐藏）。

## 升级 / 摘除

1. 关注上游 release（仓库 PR 吞吐很快，1.0.2 一天进了 20+ 条 fix）；
2. 若上游版本包含等价修复：更新 `pubspec.yaml` 的版本约束、删除
   `dependency_overrides` 段与 `vendor/adaptive_platform_ui/`，跑全量测试；
3. 若上游长期未修：同步上游新版本后，把上面那几行重新应用到新拷贝
   （diff `lib/src/toolbar/toolbar_registry.dart` 即可定位）。

回归测试：`app/test/tab_bar_owner_test.dart`。
