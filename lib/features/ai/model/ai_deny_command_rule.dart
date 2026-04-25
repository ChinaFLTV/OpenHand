enum AiDenyCommandMatchMode {
  regex('regex'),
  simple('simple');

  const AiDenyCommandMatchMode(this.storageValue);

  final String storageValue;

  static AiDenyCommandMatchMode fromStorage(String value) {
    return AiDenyCommandMatchMode.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AiDenyCommandMatchMode.simple,
    );
  }
}

class AiDenyCommandRule {
  factory AiDenyCommandRule.fromJson(Map<String, Object?> json) {
    return AiDenyCommandRule(
      id: '${json['id'] ?? ''}'.trim(),
      pattern: '${json['pattern'] ?? ''}',
      matchMode: AiDenyCommandMatchMode.fromStorage(
        '${json['match_mode'] ?? ''}',
      ),
      note: '${json['note'] ?? ''}',
    );
  }
  const AiDenyCommandRule({
    required this.id,
    required this.pattern,
    required this.matchMode,
    this.note = '',
  });

  final String id;
  final String pattern;
  final AiDenyCommandMatchMode matchMode;
  final String note;

  AiDenyCommandRule copyWith({
    String? id,
    String? pattern,
    AiDenyCommandMatchMode? matchMode,
    String? note,
  }) {
    return AiDenyCommandRule(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      matchMode: matchMode ?? this.matchMode,
      note: note ?? this.note,
    );
  }

  bool matches(String command) {
    final normalizedPattern = pattern.trim();
    final normalizedCommand = command.trim();
    if (normalizedPattern.isEmpty || normalizedCommand.isEmpty) {
      return false;
    }
    try {
      final regex = matchMode == AiDenyCommandMatchMode.regex
          ? RegExp(normalizedPattern, multiLine: true)
          : RegExp(simplePatternToRegex(normalizedPattern), multiLine: true);
      return regex.hasMatch(normalizedCommand);
    } catch (_) {
      return false;
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'pattern': pattern,
      'match_mode': matchMode.storageValue,
      'note': note,
    };
  }
}

String simplePatternToRegex(String pattern) {
  final escaped = RegExp.escape(pattern).replaceAll(r'\*', '.*');
  return '^$escaped\$';
}
