import 'ai_deny_command_rule.dart';

class AiAllowCommandRule {

  factory AiAllowCommandRule.fromJson(Map<String, Object?> json) {
    return AiAllowCommandRule(
      id: '${json['id'] ?? ''}'.trim(),
      pattern: '${json['pattern'] ?? ''}',
      matchMode: AiDenyCommandMatchMode.fromStorage(
        '${json['match_mode'] ?? ''}',
      ),
      note: '${json['note'] ?? ''}',
    );
  }
  const AiAllowCommandRule({
    required this.id,
    required this.pattern,
    required this.matchMode,
    this.note = '',
  });

  final String id;
  final String pattern;
  final AiDenyCommandMatchMode matchMode;
  final String note;

  AiAllowCommandRule copyWith({
    String? id,
    String? pattern,
    AiDenyCommandMatchMode? matchMode,
    String? note,
  }) {
    return AiAllowCommandRule(
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
