import '../../../shared/util/input_value_parsing.dart';

enum AiCommandMatchMode {
  regex('regex'),
  simple('simple');

  const AiCommandMatchMode(this.storageValue);

  final String storageValue;

  static AiCommandMatchMode fromStorage(String value) {
    return enumByStorageValueOr(
      values,
      value,
      (mode) => mode.storageValue,
      fallback: AiCommandMatchMode.simple,
    );
  }
}

abstract class AiCommandRule {
  const AiCommandRule({
    required this.id,
    required this.pattern,
    required this.matchMode,
    this.note = '',
  });

  final String id;
  final String pattern;
  final AiCommandMatchMode matchMode;
  final String note;

  bool matches(String command) {
    return aiCommandRuleMatches(
      pattern: pattern,
      matchMode: matchMode,
      command: command,
    );
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

bool aiCommandRuleMatches({
  required String pattern,
  required AiCommandMatchMode matchMode,
  required String command,
}) {
  final normalizedPattern = pattern.trim();
  final normalizedCommand = command.trim();
  if (normalizedPattern.isEmpty || normalizedCommand.isEmpty) {
    return false;
  }
  try {
    final regex = matchMode == AiCommandMatchMode.regex
        ? RegExp(normalizedPattern, multiLine: true)
        : RegExp(simplePatternToRegex(normalizedPattern), multiLine: true);
    return regex.hasMatch(normalizedCommand);
  } catch (_) {
    return false;
  }
}

String simplePatternToRegex(String pattern) {
  final escaped = RegExp.escape(pattern).replaceAll(r'\*', '.*');
  return '^$escaped\$';
}
