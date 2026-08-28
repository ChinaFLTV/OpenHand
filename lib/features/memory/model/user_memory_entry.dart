import 'package:openhand/shared/util/byte_size_format.dart';
import 'package:openhand/shared/util/text_normalization.dart';

import '../../../shared/util/text_clip.dart';

class UserMemoryEntry {
  UserMemoryEntry({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.content,
    required List<String> tags,
    this.title = '',
  }) : tags = List<String>.unmodifiable(tags);

  static const String userType = 'user';
  static const String userProfileType = 'user_profile';
  static const String autoLearnedTag = '自主学习';
  static const String userProfileEntryId = 'system:user-profile';
  static const int maxIdCharacters = 256;
  static const int maxContentCharacters = 16 * kBytesPerKiB;
  static const int maxTags = 32;
  static const int maxTagCharacters = 80;
  static const int maxTitleLength = 80;

  bool get isUserProfile => type == userProfileType;
  bool get isAutoLearned {
    final target = autoLearnedTag.toLowerCase();
    return tags.any((t) => t.toLowerCase() == target);
  }

  final String id;
  final String type;
  final DateTime createdAt;
  final String content;
  final List<String> tags;

  /// 可选的标题。空字符串表示未设置（向下兼容老数据）。优先用于 UI
  /// 卡片头部展示；为空时 UI 将退化到根据 [content] 派生的 [preview]。
  /// AI 自我学习子 Agent 会在 append/update memory 时尝试同步更新该字段。
  final String title;

  String get createdAtStorageValue => createdAt.toUtc().toIso8601String();

  String get preview {
    final normalized = content.replaceAll('\n', ' ').trim();
    if (normalized.length <= 72) {
      return normalized;
    }
    return '${clipTextByCodeUnits(normalized, 72, suffix: '')}...';
  }

  /// 用于 UI 显示的最终标题：[title] 优先；为空时回退到 [preview]。
  String get displayTitle {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return preview;
  }

  UserMemoryEntry copyWith({
    String? id,
    String? type,
    DateTime? createdAt,
    String? content,
    List<String>? tags,
    String? title,
  }) {
    return UserMemoryEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      title: title ?? this.title,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type,
      'created_at': createdAtStorageValue,
      'content': content,
      'tags': List<String>.from(tags),
      if (title.isNotEmpty) 'title': title,
    };
  }

  static String normalizeContent(String value) {
    return value.trim();
  }

  /// 标题归一化：trim + 折叠所有空白为单空格 + 截断到 [maxTitleLength]。
  /// 长度上限避免 AI 偶尔吐出整段正文当标题。
  static String normalizeTitle(String value) {
    final flat = value.replaceAll(kInlineWhitespacePattern, ' ').trim();
    return clipTextByCodeUnits(flat, maxTitleLength, suffix: '');
  }

  static List<String> normalizeTags(Iterable<String> values) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final rawValue in values) {
      final value = rawValue.trim();
      if (value.isEmpty) {
        continue;
      }
      final dedupeKey = value.toLowerCase();
      if (seen.add(dedupeKey)) {
        normalized.add(value);
      }
    }
    return normalized;
  }
}
