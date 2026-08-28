import 'package:flutter/material.dart';

import '../util/byte_size_format.dart';
import '../util/input_value_parsing.dart';

/// 将终端 ANSI SGR 转义序列解析为可渲染的 [TextSpan]。
///
/// 支持常用字体样式、前后景色、256 色和真彩色；移除光标移动、OSC 等非
/// SGR 序列。超过 [_maxParseChars] 时直接返回原文，确保解析复杂度为 O(n)。
List<TextSpan> ansiToSpans(
  String input, {
  required ColorScheme colorScheme,
  TextStyle? base,
}) {
  if (input.isEmpty) return const <TextSpan>[];
  if (input.length > _maxParseChars) {
    return <TextSpan>[TextSpan(text: input, style: base)];
  }

  final spans = <TextSpan>[];
  final state = _AnsiState();
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: state.toTextStyle(base, colorScheme),
      ),
    );
    buffer.clear();
  }

  var i = 0;
  while (i < input.length) {
    final ch = input.codeUnitAt(i);
    if (ch == 0x1b && i + 1 < input.length) {
      final next = input.codeUnitAt(i + 1);
      // CSI：ESC [ ... 字母
      if (next == 0x5b /* [ */ ) {
        final endIdx = _findCsiEnd(input, i + 2);
        if (endIdx == -1) {
          // 序列不完整时保留 ESC 原文。
          buffer.writeCharCode(ch);
          i++;
          continue;
        }
        final finalByte = input.codeUnitAt(endIdx);
        if (finalByte == 0x6d /* m */ ) {
          flush();
          final params = input.substring(i + 2, endIdx);
          state.applySgr(params);
        }
        // 移除非 SGR 的 CSI 序列。
        i = endIdx + 1;
        continue;
      }
      // OSC：ESC ] ... BEL 或 ESC \\
      if (next == 0x5d /* ] */ ) {
        final stEnd = _findOscEnd(input, i + 2);
        if (stEnd == -1) {
          buffer.writeCharCode(ch);
          i++;
          continue;
        }
        i = stEnd;
        continue;
      }
      // 移除 ESC =、ESC > 等双字节转义。
      i += 2;
      continue;
    }
    buffer.writeCharCode(ch);
    i++;
  }
  flush();
  return spans;
}

/// 使用 [base] 作为默认样式渲染 [ansiToSpans] 的结果。
Widget ansiText(
  String input, {
  required ColorScheme colorScheme,
  TextStyle? base,
  bool selectable = true,
}) {
  final spans = ansiToSpans(input, colorScheme: colorScheme, base: base);
  final rootSpan = TextSpan(style: base, children: spans);
  if (selectable) {
    return SelectableText.rich(rootSpan);
  }
  return Text.rich(rootSpan);
}

const int _maxParseChars = 200 * kBytesPerKiB;

int _findCsiEnd(String input, int start) {
  for (var i = start; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if (c >= 0x40 && c <= 0x7e) return i;
  }
  return -1;
}

int _findOscEnd(String input, int start) {
  for (var i = start; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if (c == 0x07 /* BEL */ ) return i + 1;
    if (c == 0x1b && i + 1 < input.length && input.codeUnitAt(i + 1) == 0x5c) {
      return i + 2;
    }
  }
  return -1;
}

int? _parseAnsiInt(String value) => optionalIntFromText(value);

class _AnsiState {
  bool bold = false;
  bool dim = false;
  bool italic = false;
  bool underline = false;
  bool inverse = false;
  Color? fg;
  Color? bg;

  void reset() {
    bold = false;
    dim = false;
    italic = false;
    underline = false;
    inverse = false;
    fg = null;
    bg = null;
  }

  TextStyle toTextStyle(TextStyle? base, ColorScheme colorScheme) {
    var style = base ?? const TextStyle();
    if (bold) style = style.copyWith(fontWeight: FontWeight.w700);
    if (italic) style = style.copyWith(fontStyle: FontStyle.italic);
    if (underline) {
      style = style.copyWith(decoration: TextDecoration.underline);
    }
    final effectiveFg = inverse ? bg : fg;
    final effectiveBg = inverse ? fg : bg;
    if (effectiveFg != null) {
      style = style.copyWith(
        color: dim ? effectiveFg.withValues(alpha: 0.66) : effectiveFg,
      );
    } else if (dim) {
      final c = style.color ?? colorScheme.onSurface;
      style = style.copyWith(color: c.withValues(alpha: 0.66));
    }
    if (effectiveBg != null) {
      style = style.copyWith(backgroundColor: effectiveBg);
    }
    return style;
  }

  void applySgr(String params) {
    if (params.isEmpty) {
      reset();
      return;
    }
    final parts = params.split(';');
    for (var i = 0; i < parts.length; i++) {
      final n = _parseAnsiInt(parts[i]);
      if (n == null) continue;
      switch (n) {
        case 0:
          reset();
        case 1:
          bold = true;
        case 2:
          dim = true;
        case 3:
          italic = true;
        case 4:
          underline = true;
        case 7:
          inverse = true;
        case 22:
          bold = false;
          dim = false;
        case 23:
          italic = false;
        case 24:
          underline = false;
        case 27:
          inverse = false;
        case 39:
          fg = null;
        case 49:
          bg = null;
        case 38:
          final consumed = _parseExtendedColor(parts, i + 1, isFg: true);
          if (consumed > 0) i += consumed;
        case 48:
          final consumed = _parseExtendedColor(parts, i + 1, isFg: false);
          if (consumed > 0) i += consumed;
        default:
          if (n >= 30 && n <= 37) {
            fg = _ansiBasicColor(n - 30, bright: false);
          } else if (n >= 40 && n <= 47) {
            bg = _ansiBasicColor(n - 40, bright: false);
          } else if (n >= 90 && n <= 97) {
            fg = _ansiBasicColor(n - 90, bright: true);
          } else if (n >= 100 && n <= 107) {
            bg = _ansiBasicColor(n - 100, bright: true);
          }
      }
    }
  }

  /// 返回 38/48 标记之后额外消耗的段数；格式无效时返回 0。
  int _parseExtendedColor(List<String> parts, int start, {required bool isFg}) {
    if (start >= parts.length) return 0;
    final mode = _parseAnsiInt(parts[start]);
    if (mode == 5) {
      // 256 色
      if (start + 1 >= parts.length) return 0;
      final idx = _parseAnsiInt(parts[start + 1]);
      if (idx == null) return 0;
      final color = _ansi256Color(idx);
      if (isFg) {
        fg = color;
      } else {
        bg = color;
      }
      return 2;
    }
    if (mode == 2) {
      // 真彩色
      if (start + 3 >= parts.length) return 0;
      final r = _parseAnsiInt(parts[start + 1]);
      final g = _parseAnsiInt(parts[start + 2]);
      final b = _parseAnsiInt(parts[start + 3]);
      if (r == null || g == null || b == null) return 0;
      final color = Color.fromARGB(255, r & 0xff, g & 0xff, b & 0xff);
      if (isFg) {
        fg = color;
      } else {
        bg = color;
      }
      return 4;
    }
    return 0;
  }
}

// ANSI 基础色板兼顾明暗主题，高亮色使用更高饱和度。
const List<Color> _basic = [
  Color(0xFF3F3F3F),
  Color(0xFFD6453E),
  Color(0xFF3FA45A),
  Color(0xFFC59B22),
  Color(0xFF3F7BD6),
  Color(0xFFB347C4),
  Color(0xFF1FA0A8),
  Color(0xFFBFBFBF),
];
const List<Color> _bright = [
  Color(0xFF6E6E6E),
  Color(0xFFFF6B61),
  Color(0xFF5BD27D),
  Color(0xFFE5C24A),
  Color(0xFF61A0FF),
  Color(0xFFD66BE6),
  Color(0xFF44CDD5),
  Color(0xFFF2F2F2),
];

Color _ansiBasicColor(int idx, {required bool bright}) {
  final list = bright ? _bright : _basic;
  return list[idx & 0x7];
}

Color _ansi256Color(int n) {
  if (n < 0 || n > 255) return _basic[0];
  if (n < 16) {
    return _ansiBasicColor(n & 0x7, bright: n >= 8);
  }
  if (n >= 232) {
    final v = 8 + (n - 232) * 10;
    return Color.fromARGB(255, v, v, v);
  }
  final cube = n - 16;
  final r = (cube ~/ 36) % 6;
  final g = (cube ~/ 6) % 6;
  final b = cube % 6;
  int level(int x) => x == 0 ? 0 : 55 + x * 40;
  return Color.fromARGB(255, level(r), level(g), level(b));
}
