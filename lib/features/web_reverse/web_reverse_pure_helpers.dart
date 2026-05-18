/// 纯函数辅助库——Web 逆向面板内部使用的小工具，独立成顶层公开 API
/// 以便 `test/` 直接覆盖（避免拖入 Flutter widget 依赖）。
library;

const String _vlqAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/// 解码 source-map 中的 Base64 VLQ 段（不含 `,` 与 `;` 分隔符），
/// 返回该段内全部带符号整数。空串返回空列表，未知字符直接跳过。
List<int> vlqDecode(String s) {
  final result = <int>[];
  var value = 0;
  var shift = 0;
  for (final ch in s.codeUnits) {
    final digit = _vlqAlphabet.indexOf(String.fromCharCode(ch));
    if (digit < 0) continue;
    final cont = (digit & 32) != 0;
    final data = digit & 31;
    value |= data << shift;
    if (cont) {
      shift += 5;
    } else {
      final neg = (value & 1) != 0;
      var v = value >> 1;
      if (neg) v = -v;
      result.add(v);
      value = 0;
      shift = 0;
    }
  }
  return result;
}

/// 把 console 文本归一化为聚类签名：取首行，并把 ISO 时间戳、十六进制、
/// 长数字、URL 路径中的哈希摘要、行列尾 `:L:C)` 替换为占位符，
/// 再压缩连续空白。
String normalizeConsoleSignature(String text) {
  final firstLine = text.split('\n').first.trim();
  return firstLine
      .replaceAll(
          RegExp(r'\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^\s]*'), '<ts>')
      .replaceAll(RegExp(r'\b0x[0-9a-fA-F]+\b'), '<hex>')
      .replaceAll(RegExp(r'\b\d{3,}\b'), '<num>')
      .replaceAll(RegExp(r'/[A-Fa-f0-9]{8,}'), '/<hash>')
      .replaceAll(RegExp(r':\d+:\d+\)'), ':L:C)')
      .replaceAll(RegExp(r'\s+'), ' ');
}
