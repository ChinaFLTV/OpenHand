import 'dart:convert';

import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../model/ai_dingtalk_dws_command.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiDingTalkToolSearchTool extends AiTool {
  static const int _maxResults = 12;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.dingTalkToolSearch;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final startedAt = Stopwatch()..start();
    final query = AiToolUtils.readString(
      context.decodedArguments['query'],
    ).trim();
    if (query.length > 4096) {
      return AiToolUtils.invalidResult(
        'DingTalkToolSearchTool',
        '搜索词超过 4096 个字符上限。',
      );
    }
    final maxResults = AiToolUtils.readClampedInt(
      context.decodedArguments['max_results'],
      fallback: 5,
      min: 1,
      max: _maxResults,
    );
    final searchTool = context.catalog.find(context.toolCall.name);
    final commands =
        searchTool?.dingtalkDwsCommands ?? const <AiDingTalkDwsCommand>[];
    final toolNames = <String, String>{};
    final usedNames = <String>{};
    for (final command in commands) {
      toolNames[command.cliPath] = dingtalkDwsToolName(
        command,
        usedNames: usedNames,
      );
    }
    final matches = _search(commands, query, maxResults, toolNames);
    final functions = matches
        .map(
          (command) => <String, Object?>{
            'name': toolNames[command.cliPath],
            'cli_path': command.cliPath,
            'product': command.productName,
            'description': command.description,
            'effect': command.effect,
            'risk': command.risk,
            'confirmation': command.confirmation,
            'parameters': <String, Object?>{
              'type': 'object',
              'properties': command.parameters,
              'required': command.requiredParameterNames,
              'additionalProperties': false,
            },
          },
        )
        .toList(growable: false);
    final payload = <String, Object?>{
      'query': query,
      'total': commands.length,
      'matches': matches.length,
      'functions': functions,
      'message': commands.isEmpty
          ? '当前钉钉网关未启用任何 DWS 扩展命令。'
          : matches.isEmpty
          ? '没有匹配的钉钉 DWS 工具，请更换关键词或使用 select:工具名。'
          : '再次调用 DingTalkToolSearchTool，并提供 tool_name 与 arguments 执行对应 DWS 能力。',
    };
    return AiToolUtils.simpleSuccessResult(
      command: 'DingTalkToolSearch query=$query',
      output: jsonEncode(payload),
      durationMs: startedAt.elapsedMilliseconds,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'dingtalk_tool_search_query': query,
        'dingtalk_tool_search_total': commands.length,
        'dingtalk_tool_search_matches': matches.length,
      },
    );
  }

  List<AiDingTalkDwsCommand> _search(
    List<AiDingTalkDwsCommand> commands,
    String query,
    int maxResults,
    Map<String, String> toolNames,
  ) {
    if (query.isEmpty) return commands.take(maxResults).toList(growable: false);
    final lower = query.toLowerCase();
    if (lower.startsWith('select:')) {
      final requested = splitTrimmedNonEmpty(query.substring(7));
      final wanted = requested.map((item) => item.toLowerCase()).toSet();
      return commands
          .where(
            (item) =>
                wanted.contains(
                  (toolNames[item.cliPath] ?? '').toLowerCase(),
                ) ||
                wanted.contains(item.cliPath.toLowerCase()),
          )
          .take(maxResults)
          .toList(growable: false);
    }
    final terms = lower
        .split(kInlineWhitespacePattern)
        .where((item) => item.isNotEmpty)
        .map((item) => item.startsWith('+') ? item.substring(1) : item)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final scored = <(AiDingTalkDwsCommand, int)>[];
    for (final command in commands) {
      final haystack = [
        toolNames[command.cliPath] ?? dingtalkDwsToolName(command),
        command.cliPath,
        command.productId,
        command.productName,
        command.description,
        command.summary,
      ].join(' ').toLowerCase();
      var score = 0;
      for (final term in terms) {
        if (haystack.contains(term)) score += 1;
      }
      if (score > 0) scored.add((command, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored
        .take(maxResults)
        .map((item) => item.$1)
        .toList(growable: false);
  }
}
