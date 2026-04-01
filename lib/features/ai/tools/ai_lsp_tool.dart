import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

/// 2026-04-01 LSP 符号级导航工具
/// 蓝图映射自 claude-code-sourcemap LSPTool.ts
class AiLspTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.lsp;

  @override
  List<String> get aliases => const <String>['Lsp'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    
    final operation = '${args['operation'] ?? ''}'.trim();
    final filePath = '${args['file_path'] ?? ''}'.trim();
    
    if (operation.isEmpty || filePath.isEmpty) {
      return AiToolUtils.invalidResult('Lsp', 'operation and file_path are required.');
    }

    final rootPath = AiToolUtils.resolvePath(filePath);

    // TODO: Connect to concrete Analysis Server / LSP Manager.
    // 现阶段按需返回占位提示，通知模型依赖后备模式搜索
    final output = 'LSP operation $operation on $filePath is not yet bound to the LSP daemon. '
        'Please use grep/glob/read as fallback for code intelligence.';

    return AiToolUtils.simpleSuccessResult(
      command: 'Lsp $operation',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: rootPath,
    );
  }
}
