import 'dart:convert';

import 'package:flutter/services.dart'
    show TextEditingValue, TextRange, TextSelection;

/// Base64 编解码 — V2EX「联系方式防爬虫」场景（V2EX Polish 同款交互）：
/// 发帖/回复把微信号、手机号编码后再发（编辑器「Base64」按钮），阅读端
/// 点击识别出的 base64 串即可解码查看（`Mv2RichText`）。
abstract final class Base64Text {
  /// 正文里一段可疑的 base64：≥12 位标准字符表 + 可选 padding。阈值取
  /// 核心字符 12：8 位微信号编码后核心 11~12，11 位手机号编码后核心 15，
  /// 而普通英文单词几乎到不了 12 位。真正的门槛在 [tryDecode] 的合法性
  /// 校验，这里只负责把候选圈出来。
  static final RegExp candidatePattern = RegExp(r'[A-Za-z0-9+/]{12,}={0,2}');

  /// 尝试把 [value] 按 UTF-8 严格解码；不是合法 base64 或解码结果不是
  /// 合法文本（乱码、含控制字符）时返回 null。
  ///
  /// 联系方式大多是中文混排（UTF-8 编码），所以校验走 UTF-8 合法性而不
  /// 是旧实现的「ASCII 可打印占比」——后者会把「微信：xxx」这类结果整体
  /// 拒掉。随机单词碰巧解码成功的漏网情况由「必须是合法 UTF-8 + 无控制
  /// 字符」两道闸压到可用水平。
  static String? tryDecode(String value) {
    final core = value.replaceAll('=', '');
    if (core.length < 12) return null;
    // 站上常有人手贴去掉 padding 的编码串，补齐再解。
    final padded = core + '=' * ((4 - core.length % 4) % 4);
    try {
      final bytes = base64.decode(padded);
      final decoded = utf8.decode(bytes, allowMalformed: false);
      final hasControl = decoded.runes.any(
        (rune) =>
            rune < 0x20 && rune != 0x0A && rune != 0x0D && rune != 0x09,
      );
      return hasControl ? null : decoded;
    } on FormatException {
      return null;
    }
  }

  /// UTF-8 编码（V2EX 站上贴的 base64 都是 utf8 文本编码）。
  static String encode(String value) => base64.encode(utf8.encode(value));

  /// 把 [value] 中选中的文本原位编码为 Base64，光标落在编码结果之后。
  /// 调用方需先确认选区有效（未选中时交给 UI 提示，不打扰这里）。
  static TextEditingValue encodeSelection(TextEditingValue value) {
    final text = value.text;
    final selection = value.selection;
    final selected = selection.textInside(text);
    final encoded = encode(selected);
    return value.copyWith(
      text: text.replaceRange(selection.start, selection.end, encoded),
      selection: TextSelection.collapsed(
        offset: selection.start + encoded.length,
      ),
      composing: TextRange.empty,
    );
  }
}
