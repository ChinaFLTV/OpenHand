class UserMemoryEntry {
  const UserMemoryEntry({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.content,
    required this.tags,
  });

  static const String userType = 'user';
  static const String userProfileType = 'user_profile';
  static const String autoLearnedTag = '自主学习';
  static const String userProfileEntryId = 'system:user-profile';

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

  String get createdAtStorageValue => createdAt.toUtc().toIso8601String();

  String get preview {
    final normalized = content.replaceAll('\n', ' ').trim();
    if (normalized.length <= 72) {
      return normalized;
    }
    return '${normalized.substring(0, 72)}...';
  }

  UserMemoryEntry copyWith({
    String? id,
    String? type,
    DateTime? createdAt,
    String? content,
    List<String>? tags,
  }) {
    return UserMemoryEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      content: content ?? this.content,
      tags: tags ?? this.tags,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type,
      'created_at': createdAtStorageValue,
      'content': content,
      'tags': List<String>.from(tags),
    };
  }

  static String normalizeContent(String value) {
    return value.trim();
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
