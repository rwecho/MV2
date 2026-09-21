import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dart half of the `mv2/clipboard` channel.
///
/// iOS 16 起代码读取剪贴板会弹「允许粘贴」确认，而 MV2 的剪贴板链接检测
/// 每次冷启动/回前台都会读一次 —— 于是每次打开都弹。这个探针暴露两个
/// Apple 提供的**无提示**检测接口，让 Dart 在真正读内容前先过两道零成本
/// 闸门：剪贴板变过没有（`changeCount`）、是不是疑似网页链接
/// （`detectPatterns(.probableWebURL)`）。两道都过才读内容——系统弹窗只
/// 会在「剪贴板真的是新链接」时出现一次。
class ClipboardProbe {
  const ClipboardProbe({this.channel = _defaultChannel});

  /// Keep in sync with `MV2NativeBridge.swift` (iOS) and `MainActivity.kt`
  /// (Android).
  static const MethodChannel _defaultChannel = MethodChannel('mv2/clipboard');

  /// Injectable so tests can substitute a mock handler.
  final MethodChannel channel;

  /// 系统剪贴板的变更计数。
  ///
  /// `null` 表示平台没有这个能力：测试/未接原生侧（MissingPluginException）
  /// 返回 null；Android 的 ClipboardManager 没有计数 API，原生侧返回 -1 也
  /// 归一为 null —— 调用方应跳过「计数没变就跳过」的闸门，保持旧行为。
  Future<int?> changeCount() async {
    try {
      final value = await channel.invokeMethod<int>('changeCount');
      if (value == null || value < 0) return null;
      return value;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 剪贴板内容是否疑似网页链接（iOS 16+ 的 detectPatterns，不触发粘贴
  /// 确认）。`false` = 确认不是链接；`null`/`true` = 无法确定，按可能是
  /// 链接处理（回退到真正读取的旧行为）。
  Future<bool?> hasProbableWebURL() async {
    try {
      return await channel.invokeMethod<bool>('hasProbableWebURL');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

final clipboardProbeProvider = Provider<ClipboardProbe>(
  (ref) => const ClipboardProbe(),
);
