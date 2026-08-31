import 'dart:convert';

import '../../../app/support/silent_log.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_normalization.dart';

String parseBashToolCommandFromArguments(String rawArguments) {
  return _readToolArgumentValue(
    rawArguments,
    preferredKeys: const <String>['cmd', 'command'],
  );
}

String parseBashToolWorkingDirectoryFromArguments(String rawArguments) {
  return _readToolArgumentValue(
    rawArguments,
    preferredKeys: const <String>['working_directory', 'cwd'],
  );
}

String _readToolArgumentValue(
  String rawArguments, {
  required List<String> preferredKeys,
}) {
  final trimmed = rawArguments.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      return _readPreferredArgumentValue(
        stringKeyedMapFromValue(decoded),
        preferredKeys,
      );
    }
    return '';
  } catch (_) {
    // 上游可能把多个 tool_call 参数拼成 `{...}{...}`，先尝试恢复再记录异常。
    final concatMerged = _mergeConcatenatedJsonObjects(trimmed);
    if (concatMerged != null) {
      return _readPreferredArgumentValue(concatMerged, preferredKeys);
    } else {
      // 流式参数未闭合属于预期中间态，不重复输出日志。
      final looksIncomplete =
          trimmed.codeUnitAt(0) == 0x7B &&
          _findBalancedObjectEnd(trimmed, 0) < 0;
      if (!looksIncomplete) {
        silentLog(
          'tool_call_argument_parser',
          '解码工具参数 JSON',
          '无法恢复：${_truncateForLog(trimmed)}',
        );
      }
    }
  }
  return _readPartialJsonStringField(trimmed, preferredKeys);
}

String _readPreferredArgumentValue(
  Map<String, Object?> argumentsMap,
  List<String> preferredKeys,
) {
  for (final key in preferredKeys) {
    final value = argumentsMap[key];
    final normalized = '${value ?? ''}'.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}

/// 拆分并合并连续的完整 JSON 对象；格式不匹配时返回空值。
Map<String, Object?>? _mergeConcatenatedJsonObjects(String source) {
  if (source.isEmpty || source.codeUnitAt(0) != 0x7B) {
    return null;
  }
  final merged = <String, Object?>{};
  var cursor = 0;
  var foundAny = false;
  while (cursor < source.length) {
    while (cursor < source.length &&
        isAsciiWhitespaceCodeUnit(source.codeUnitAt(cursor))) {
      cursor += 1;
    }
    if (cursor >= source.length) break;
    if (source.codeUnitAt(cursor) != 0x7B) {
      // 尾部存在非对象内容，不能按连续对象恢复。
      return null;
    }
    final end = _findBalancedObjectEnd(source, cursor);
    if (end < 0) {
      return null;
    }
    final slice = source.substring(cursor, end + 1);
    try {
      final decoded = jsonDecode(slice);
      if (decoded is Map) {
        merged.addAll(stringKeyedMapFromValue(decoded));
        foundAny = true;
      } else {
        return null;
      }
    } catch (_) {
      return null;
    }
    cursor = end + 1;
  }
  return foundAny ? merged : null;
}

/// 返回 [start] 对应 JSON 对象的闭合位置；未闭合时返回 -1。
int _findBalancedObjectEnd(String source, int start) {
  var depth = 0;
  var inString = false;
  var escape = false;
  for (var i = start; i < source.length; i++) {
    final c = source.codeUnitAt(i);
    if (inString) {
      if (escape) {
        escape = false;
      } else if (c == 0x5C) {
        escape = true;
      } else if (c == 0x22) {
        inString = false;
      }
      continue;
    }
    if (c == 0x22) {
      inString = true;
    } else if (c == 0x7B || c == 0x5B) {
      depth += 1;
    } else if (c == 0x7D || c == 0x5D) {
      depth -= 1;
      if (depth == 0 && c == 0x7D) {
        return i;
      }
      if (depth < 0) {
        return -1;
      }
    }
  }
  return -1;
}

String _truncateForLog(String value, {int max = 160}) {
  if (value.length <= max) return value;
  return clipTextByCodeUnits(value, max, suffix: '…（原文 ${value.length} 个字符）');
}

String _readPartialJsonStringField(String source, List<String> preferredKeys) {
  for (final key in preferredKeys) {
    final value = _readSinglePartialJsonStringField(source, key);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _readSinglePartialJsonStringField(String source, String key) {
  final quotedKey = '"$key"';
  final keyIndex = source.indexOf(quotedKey);
  if (keyIndex == -1) {
    return '';
  }
  var cursor = keyIndex + quotedKey.length;
  while (cursor < source.length &&
      isAsciiWhitespaceCodeUnit(source.codeUnitAt(cursor))) {
    cursor += 1;
  }
  if (cursor >= source.length || source.codeUnitAt(cursor) != 0x3A) {
    return '';
  }
  cursor += 1;
  while (cursor < source.length &&
      isAsciiWhitespaceCodeUnit(source.codeUnitAt(cursor))) {
    cursor += 1;
  }
  if (cursor >= source.length || source.codeUnitAt(cursor) != 0x22) {
    return '';
  }
  cursor += 1;

  final buffer = StringBuffer();
  while (cursor < source.length) {
    final codeUnit = source.codeUnitAt(cursor);
    if (codeUnit == 0x22) {
      return buffer.toString().trim();
    }
    if (codeUnit == 0x5C) {
      cursor += 1;
      if (cursor >= source.length) {
        buffer.write(r'\');
        break;
      }
      final escapedCodeUnit = source.codeUnitAt(cursor);
      switch (escapedCodeUnit) {
        case 0x22:
          buffer.write('"');
        case 0x5C:
          buffer.write(r'\');
        case 0x2F:
          buffer.write('/');
        case 0x62:
          buffer.write('\b');
        case 0x66:
          buffer.write('\f');
        case 0x6E:
          buffer.write('\n');
        case 0x72:
          buffer.write('\r');
        case 0x74:
          buffer.write('\t');
        case 0x75:
          if (cursor + 4 < source.length) {
            final hex = source.substring(cursor + 1, cursor + 5);
            final parsed = optionalIntFromText(hex, radix: 16);
            if (parsed != null) {
              buffer.write(String.fromCharCode(parsed));
              cursor += 4;
              break;
            }
          }
          buffer.write(r'\u');
        default:
          buffer.writeCharCode(escapedCodeUnit);
      }
      cursor += 1;
      continue;
    }
    buffer.writeCharCode(codeUnit);
    cursor += 1;
  }
  return buffer.toString().trim();
}
