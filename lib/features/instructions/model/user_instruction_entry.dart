/// User Instructions feature — model
///
/// 单条用户自定义指令的不可变描述。指令在以下两个位置使用：
///   1. 全局指令模块（侧边栏 → 指令）— UI 编辑/排序/启停。
///   2. 各线程模板的 system prompt 拼装阶段 — 启用且未被本轮对话临时
///      取消的指令会以独立"用户指令"段落注入提示词。
library;

import 'package:openhand/shared/util/byte_size_format.dart';
import 'package:openhand/shared/util/text_normalization.dart';

import '../../../shared/util/text_clip.dart';


class UserInstructionEntry {
  const UserInstructionEntry({
    required this.id,
    required this.name,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.sortOrder,
    this.description = '',
    this.version = '1.0',
    this.applyTo = '',
    this.notes = const <String>[],
    this.taskTypes = const <String>[],
    this.keywords = const <String>[],
    this.enabled = true,
  });

  final String id;
  final String name;

  /// 指令正文（Markdown），将被注入到 system prompt 的"用户指令"段落里。
  final String body;

  final String description;
  final String version;

  /// 自由文本，描述指令在何种任务上下文下加载（仅元数据展示，不参与匹配）。
  final String applyTo;

  /// 配套备注（每条单独一行，UI 列表展示）。
  final List<String> notes;

  /// `trigger.taskTypes` 元数据（仅展示，运行时全部启用 = 注入）。
  final List<String> taskTypes;

  /// `trigger.keywords` 元数据。
  final List<String> keywords;

  final bool enabled;

  /// 用于稳定排序；越小越靠前。控制器维护其单调递增，编辑器支持改动。
  final int sortOrder;

  final DateTime createdAt;
  final DateTime updatedAt;

  UserInstructionEntry copyWith({
    String? id,
    String? name,
    String? body,
    String? description,
    String? version,
    String? applyTo,
    List<String>? notes,
    List<String>? taskTypes,
    List<String>? keywords,
    bool? enabled,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserInstructionEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      body: body ?? this.body,
      description: description ?? this.description,
      version: version ?? this.version,
      applyTo: applyTo ?? this.applyTo,
      notes: notes ?? this.notes,
      taskTypes: taskTypes ?? this.taskTypes,
      keywords: keywords ?? this.keywords,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'body': body,
      'description': description,
      'version': version,
      'apply_to': applyTo,
      'notes': List<String>.from(notes),
      'task_types': List<String>.from(taskTypes),
      'keywords': List<String>.from(keywords),
      'enabled': enabled,
      'sort_order': sortOrder,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  // === 静态约束 / 工具 ===

  static const int maxNameLength = 80;
  static const int maxDescriptionLength = 240;
  static const int maxApplyToLength = 240;
  static const int maxNoteLength = 240;
  static const int maxNotes = 20;
  static const int maxTaskTypes = 20;
  static const int maxKeywords = 30;
  static const int maxBodyLength = 64 * kBytesPerKiB;

  static String normalizeName(String value) {
    final flat = value.replaceAll(kInlineWhitespacePattern, ' ').trim();
    return clipTextByCodeUnits(flat, maxNameLength, suffix: '');
  }

  static String normalizeOneLine(String value, int max) {
    final flat = value.replaceAll(kInlineWhitespacePattern, ' ').trim();
    return clipTextByCodeUnits(flat, max, suffix: '');
  }

  static String normalizeBody(String value) {
    final trimmed = value.trim();
    return clipTextByCodeUnits(trimmed, maxBodyLength, suffix: '');
  }

  static String normalizeVersion(String value) {
    final flat = value.trim();
    if (flat.isEmpty) return '1.0';
    return clipTextByCodeUnits(flat, 32, suffix: '');
  }

  static List<String> normalizeStringList(
    Iterable<String> values, {
    required int maxItems,
    required int maxItemLength,
    bool dedupeCaseInsensitive = false,
  }) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      final clipped = clipTextByCodeUnits(value, maxItemLength, suffix: '');
      final key = dedupeCaseInsensitive ? clipped.toLowerCase() : clipped;
      if (seen.add(key)) out.add(clipped);
      if (out.length >= maxItems) break;
    }
    return out;
  }
}
