import 'package:flutter/material.dart';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';

Object? coerceMcpPayloadValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final decoded = tryDecodeJson(trimmed);
  if (decoded != null) return decoded;
  final lower = trimmed.toLowerCase();
  if (lower == 'true') return true;
  if (lower == 'false') return false;
  if (lower == 'null') return null;
  return int.tryParse(trimmed) ?? double.tryParse(trimmed) ?? trimmed;
}

Map<String, Object?>? parseMcpLoosePayloadMap(String text) {
  if (!text.startsWith('{') || !text.endsWith('}')) return null;
  final inner = text.substring(1, text.length - 1).trim();
  if (inner.isEmpty) return const <String, Object?>{};
  final matches = RegExp(
    r'(?:^|,\s*)([A-Za-z_][A-Za-z0-9_.-]{0,64}):\s*',
  ).allMatches(inner).toList(growable: false);
  if (matches.isEmpty) return null;

  final result = <String, Object?>{};
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final end = index + 1 < matches.length
        ? matches[index + 1].start
        : inner.length;
    var value = inner.substring(match.end, end).trim();
    if (value.endsWith(',')) {
      value = value.substring(0, value.length - 1).trimRight();
    }
    result[match.group(1)!.trim()] = coerceMcpPayloadValue(value);
  }
  return result;
}

String mcpPayloadScalarText(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value.trim();
  if (value is num || value is bool) return '$value';
  if (value is Map || value is List) return prettyPrintJson(value);
  return '$value'.trim();
}

bool mcpPayloadPrefersMonospace(String key, String value) {
  final normalizedKey = key.toLowerCase();
  return normalizedKey.contains('command') ||
      normalizedKey.contains('path') ||
      normalizedKey.contains('stdout') ||
      normalizedKey.contains('stderr') ||
      normalizedKey.contains('code') ||
      value.contains('\n') ||
      value.contains('&&') ||
      value.contains('://');
}

String mcpPayloadShapeLabel(
  BuildContext context,
  Object? value,
  bool structured,
) {
  if (!structured) {
    return openHandLocalizedText(context, zh: '原始文本', en: 'Plain text');
  }
  if (value is Map) {
    return openHandLocalizedText(context, zh: '对象结构', en: 'Object');
  }
  if (value is List) {
    return openHandLocalizedText(context, zh: '列表结构', en: 'Array');
  }
  return openHandLocalizedText(context, zh: '结构化', en: 'Structured');
}

String mcpPayloadCountLabel(BuildContext context, Object? value) {
  if (value is Map) {
    return openHandLocalizedText(
      context,
      zh: '${value.length} 个字段',
      en: '${value.length} fields',
    );
  }
  if (value is List) {
    return openHandLocalizedText(
      context,
      zh: '${value.length} 项',
      en: '${value.length} items',
    );
  }
  return openHandLocalizedText(context, zh: '1 段内容', en: '1 segment');
}

String mcpPayloadSizeLabel(BuildContext context, String text) {
  return openHandLocalizedText(
    context,
    zh: '${text.length} 字符',
    en: '${text.length} chars',
  );
}

String mcpPayloadTypeLabel(BuildContext context, Object? value) {
  if (value is Map) {
    return openHandLocalizedText(context, zh: '对象', en: 'Object');
  }
  if (value is List) {
    return openHandLocalizedText(context, zh: '列表', en: 'Array');
  }
  if (value is num) {
    return openHandLocalizedText(context, zh: '数值', en: 'Number');
  }
  if (value is bool) {
    return openHandLocalizedText(context, zh: '布尔', en: 'Boolean');
  }
  if (value == null) {
    return openHandLocalizedText(context, zh: '空值', en: 'Null');
  }
  return openHandLocalizedText(context, zh: '文本', en: 'Text');
}

String mcpPayloadContentLabel(
  BuildContext context,
  String semanticKey,
  bool monospace,
) {
  final key = semanticKey.toLowerCase();
  if (key.contains('command')) {
    return openHandLocalizedText(context, zh: 'Shell 命令', en: 'Shell command');
  }
  if (key.contains('stdout') || key.contains('stderr')) {
    return openHandLocalizedText(context, zh: '终端输出', en: 'Terminal output');
  }
  if (key.contains('path')) {
    return openHandLocalizedText(context, zh: '文件路径', en: 'File path');
  }
  if (monospace) {
    return openHandLocalizedText(context, zh: '等宽文本', en: 'Monospace text');
  }
  return openHandLocalizedText(context, zh: '长文本', en: 'Long text');
}

IconData mcpPayloadValueIcon(Object? value) {
  if (value is Map) return Icons.data_object_rounded;
  if (value is List) return Icons.data_array_rounded;
  if (value is num) return Icons.pin_rounded;
  if (value is bool) return Icons.toggle_on_rounded;
  if (value == null) return Icons.block_rounded;
  return Icons.short_text_rounded;
}

/// 结构化载荷分层列表的项间距。
const double kMcpPayloadEntrySpacing = 9;

/// 把结构化载荷的一层渲染为纵向列表：逐项调 [fieldBuilder]，
/// 末项不留下边距，被截断时追加一条 [overflowBuilder] 提示。
///
/// MCP 运维面板与写调用审批弹窗各自把 Map / List 两个分支都抄了一遍（合计
/// 四份），间距、末项去间距、溢出提示的挂载条件全靠人工对齐，改一处必漏三处。
Widget buildMcpPayloadEntryColumn<T>({
  required List<T> visible,
  required int hiddenCount,
  required Widget Function(int index, T item) fieldBuilder,
  required Widget Function(int hiddenCount) overflowBuilder,
  double spacing = kMcpPayloadEntrySpacing,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final entry in visible.indexed)
        Padding(
          padding: EdgeInsets.only(
            bottom: entry.$1 == visible.length - 1 && hiddenCount <= 0
                ? 0
                : spacing,
          ),
          child: fieldBuilder(entry.$1, entry.$2),
        ),
      if (hiddenCount > 0) overflowBuilder(hiddenCount),
    ],
  );
}
