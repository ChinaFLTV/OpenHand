import '../../../shared/util/input_value_parsing.dart';
import 'ai_command_rule.dart';

class AiDenyCommandRule extends AiCommandRule {
  factory AiDenyCommandRule.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiDenyCommandRule(
      id: stringFromValue(json['id']),
      pattern: stringFromValue(json['pattern']),
      matchMode: AiCommandMatchMode.fromStorage(
        stringFromValue(json['match_mode']),
      ),
      note: stringFromValue(json['note']),
    );
  }
  const AiDenyCommandRule({
    required super.id,
    required super.pattern,
    required super.matchMode,
    super.note,
  });

  AiDenyCommandRule copyWith({
    String? id,
    String? pattern,
    AiCommandMatchMode? matchMode,
    String? note,
  }) {
    return AiDenyCommandRule(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      matchMode: matchMode ?? this.matchMode,
      note: note ?? this.note,
    );
  }
}
