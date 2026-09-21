/// Bitcoin/Solana Base58 编解码（无校验和版本 —— Solana 地址与 Phantom
/// 导出的私钥都是裸 base58，不是 base58check）。
///
/// 自带实现而不是引入依赖：只有一个 58 字符的字母表加一段大数除法，
/// 输入上限是 64 字节的私钥/32 字节的公钥，性能与正确性都容易测试。
abstract final class Base58 {
  /// 排除了易混淆的 `0OIl` 的标准字母表。
  static const String _alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  static const String _charsetError = '包含 Base58 之外的字符';

  /// Encodes [bytes]; every leading `0x00` byte becomes a `1`.
  static String encode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    var zeros = 0;
    while (zeros < bytes.length && bytes[zeros] == 0) {
      zeros++;
    }
    // 大数除法：每次整体除以 58，余数即当前位。256 进制数组原地缩。
    final digits = List<int>.of(bytes);
    final output = <String>[];
    var start = zeros;
    while (start < digits.length) {
      var remainder = 0;
      for (var i = start; i < digits.length; i++) {
        final value = remainder * 256 + digits[i];
        digits[i] = value ~/ 58;
        remainder = value % 58;
      }
      // 去掉这一轮高位产生的 0。
      while (start < digits.length && digits[start] == 0) {
        start++;
      }
      output.add(_alphabet[remainder]);
    }
    return '1' * zeros + output.reversed.join();
  }

  /// Decodes [input]; throws [FormatException] on any non-alphabet character.
  static List<int> decode(String input) {
    if (input.isEmpty) return <int>[];
    var zeros = 0;
    while (zeros < input.length && input[zeros] == '1') {
      zeros++;
    }
    final bytes = <int>[];
    for (var i = zeros; i < input.length; i++) {
      final value = _alphabet.indexOf(input[i]);
      if (value < 0) {
        throw FormatException(_charsetError);
      }
      var carry = value;
      for (var j = 0; j < bytes.length; j++) {
        carry += bytes[j] * 58;
        bytes[j] = carry & 0xff;
        carry >>= 8;
      }
      while (carry > 0) {
        bytes.add(carry & 0xff);
        carry >>= 8;
      }
    }
    final result = <int>[...List<int>.filled(zeros, 0), ...bytes.reversed];
    return result;
  }
}
