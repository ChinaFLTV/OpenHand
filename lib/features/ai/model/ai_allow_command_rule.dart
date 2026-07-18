import '../../../shared/util/input_value_parsing.dart';
import 'ai_command_rule.dart';

class AiAllowCommandRule extends AiCommandRule {
  factory AiAllowCommandRule.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiAllowCommandRule(
      id: stringFromValue(json['id']),
      pattern: stringFromValue(json['pattern']),
      matchMode: AiCommandMatchMode.fromStorage(
        stringFromValue(json['match_mode']),
      ),
      note: stringFromValue(json['note']),
    );
  }
  const AiAllowCommandRule({
    required super.id,
    required super.pattern,
    required super.matchMode,
    super.note,
  });

  AiAllowCommandRule copyWith({
    String? id,
    String? pattern,
    AiCommandMatchMode? matchMode,
    String? note,
  }) {
    return AiAllowCommandRule(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      matchMode: matchMode ?? this.matchMode,
      note: note ?? this.note,
    );
  }
}
