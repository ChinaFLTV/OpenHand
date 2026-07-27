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

/// 判断命令是否命中规则。
///
/// `multiLine: true` 是刻意的：多行命令里任意一行命中即算命中。本函数唯一的
/// 执行期用途是拦截方向的 deny 规则（[AiBashToolService] 逐条比对），放宽匹配
/// 只会拦得更多，方向上是安全的。放行方向的 allow 规则只进提示词、不参与放行
/// 判定，所以这里不存在「首行命中即整条豁免」的问题——改成单行锚定反而会让
/// `a\nrm -rf /` 这类多行命令绕过 deny。
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
