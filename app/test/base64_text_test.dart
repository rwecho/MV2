import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/text/base64_text.dart';

/// Base64 编解码工具契约：正文识别（candidatePattern + tryDecode）与编辑器
/// 选区编码（encodeSelection）。联系方式的「中文混排 UTF-8」是主场景，
/// 解码校验必须放行中文、拦住乱码与随机词。
void main() {
  group('candidatePattern', () {
    test('11 位手机号的编码串（16 字符）命中', () {
      expect(
        Base64Text.candidatePattern.hasMatch('MTM4MDAxMzgwMDA='),
        isTrue,
      );
    });

    test('普通短句不命中', () {
      expect(Base64Text.candidatePattern.hasMatch('hello world'), isFalse);
    });
  });

  group('tryDecode', () {
    test('ASCII（手机号）解码', () {
      expect(Base64Text.tryDecode('MTM4MDAxMzgwMDA='), '13800138000');
    });

    test('中文混排联系方式解码（UTF-8 主场景）', () {
      const contact = '微信：mv2-fans，备注 V2EX';
      expect(Base64Text.tryDecode(Base64Text.encode(contact)), contact);
    });

    test('无 padding 的编码串补齐后解码', () {
      // 「13800138000」的编码去掉末尾 `=`，站上手贴常这样。
      expect(Base64Text.tryDecode('MTM4MDAxMzgwMDA'), '13800138000');
    });

    test('核心字符不足 12 位不当作 base64', () {
      expect(Base64Text.tryDecode('MTM4MDAxMzg='), isNull);
    });

    test('解码出控制字符的串拒绝', () {
      // base64([0x01] * 12)：解码合法但内容是控制字符 —— 不是给人看的文本。
      expect(Base64Text.tryDecode('AQEBAQEBAQEBAQEB'), isNull);
    });

    test('非法 UTF-8 的解码结果拒绝', () {
      // base64([0xFF] * 12)：解码出的字节构不成合法 UTF-8。
      expect(Base64Text.tryDecode('////////////////'), isNull);
    });

    test('随机英文字母串大概率不是合法 UTF-8', () {
      expect(Base64Text.tryDecode('abcdefghijklmnop'), isNull);
    });
  });

  group('encodeSelection', () {
    test('只编码选区，光标落在编码结果之后', () {
      // 'name: secret123'，选中 'secret123'（offset 6..15）。
      const value = TextEditingValue(
        text: 'name: secret123',
        selection: TextSelection(baseOffset: 6, extentOffset: 15),
      );
      final encoded = Base64Text.encodeSelection(value);
      expect(encoded.text, 'name: c2VjcmV0MTIz');
      expect(encoded.selection.baseOffset, 18);
    });

    test('编码结果可被 tryDecode 还原', () {
      const original = '微信：mv2-fans';
      final value = TextEditingValue(
        text: '联系方式：$original',
        selection: TextSelection(
          baseOffset: '联系方式：'.length,
          extentOffset: '联系方式：$original'.length,
        ),
      );
      final encoded = Base64Text.encodeSelection(value);
      expect(
        Base64Text.tryDecode(
          encoded.text.substring('联系方式：'.length),
        ),
        original,
      );
    });
  });
}
