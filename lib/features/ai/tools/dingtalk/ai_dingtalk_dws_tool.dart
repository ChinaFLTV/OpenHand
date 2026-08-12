import 'dart:convert';

import '../../../../shared/util/async_concurrency.dart';
import '../../model/ai_dingtalk_dws_command.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

typedef AiDingTalkDwsExecutor =
    Future<Object?> Function({
      required AiDingTalkDwsCommand command,
      required Map<String, Object?> arguments,
      required String workingDirectory,
      Future<void>? cancelSignal,
    });

class AiDingTalkDwsTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.dingtalkDws;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final tool =
        context.catalog.find(context.toolCall.name) ??
        context.catalog.findDeferredTool(context.toolCall.name);
    final command = tool?.dingtalkDwsCommand;
    if (command == null) {
      return AiToolUtils.invalidResult(
        context.toolCall.name,
        '钉钉 DWS 工具目录已失效，请重新使用 DingTalkToolSearchTool 搜索。',
      );
    }
    final executor = context.metadata['dingtalk_dws_executor'];
    if (executor is! AiDingTalkDwsExecutor) {
      return AiToolUtils.invalidResult(command.cliPath, '钉钉 DWS 执行器不可用。');
    }
    final arguments = <String, Object?>{};
    for (final key in command.parameters.keys) {
      if (context.decodedArguments.containsKey(key)) {
        arguments[key] = context.decodedArguments[key];
      }
    }
    for (final key in context.decodedArguments.keys) {
      if (!command.parameters.containsKey(key)) {
        return AiToolUtils.invalidResult(command.cliPath, '不支持的参数：$key。');
      }
    }
    for (final entry in command.parameters.entries) {
      final schema = entry.value is Map
          ? Map<String, Object?>.from(entry.value as Map)
          : const <String, Object?>{};
      if (schema['required'] == true && _isMissing(arguments[entry.key])) {
        return AiToolUtils.invalidResult(
          command.cliPath,
          '缺少必填参数：${entry.key}。',
        );
      }
    }
    final isWrite = command.effect.toLowerCase() != 'read';
    final requiresConfirmation =
        command.confirmation.toLowerCase() == 'user_required' ||
        (isWrite && context.requireWriteCommandConfirmation);
    if (requiresConfirmation) {
      final confirm = context.confirmWriteCommand;
      if (confirm == null) {
        return AiToolUtils.invalidResult(command.cliPath, '该钉钉 DWS 写操作需要用户确认。');
      }
      final decision = await confirm(
        BashCommandApprovalRequest(
          command: command.cliPath,
          workingDirectory: _workingDirectory(context),
          isWriteCommand: true,
          requestedAt: DateTime.now(),
        ),
      );
      if (decision != BashCommandApprovalDecision.approved) {
        return AiToolExecutionResult(
          status: BashToolExecutionStatus.rejected,
          command: command.cliPath,
          workingDirectory: _workingDirectory(context),
          stdout: '',
          stderr: '用户未批准该钉钉 DWS 写操作。',
          durationMs: 0,
          resultText: 'status: rejected\nerror: 用户未批准该钉钉 DWS 写操作。',
          isWriteCommand: true,
          metadata: <String, Object?>{
            'tool_source': 'dingtalk_dws',
            'dingtalk_dws_confirmation_decision':
                bashCommandApprovalDecisionValue(decision),
          },
        );
      }
    }
    if (await isCancelSignalCompleted(context.cancelSignal)) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.cancelled,
        command: command.cliPath,
        workingDirectory: _workingDirectory(context),
        stdout: '',
        stderr: '钉钉 DWS 工具执行已取消。',
        durationMs: 0,
        resultText: 'status: cancelled\nerror: 钉钉 DWS 工具执行已取消。',
        metadata: const <String, Object?>{
          'tool_source': 'dingtalk_dws',
          'execution_cancelled': true,
        },
      );
    }
    final startedAt = Stopwatch()..start();
    try {
      final raw = await executor(
        command: command,
        arguments: arguments,
        workingDirectory: _workingDirectory(context),
        cancelSignal: context.cancelSignal,
      );
      final result = raw is Map
          ? Map<String, Object?>.from(raw)
          : <String, Object?>{'stdout': '$raw'};
      final stdout = '${result['stdout'] ?? ''}';
      final timedOut = result['timed_out'] == true;
      final cancelled = result['cancelled'] == true;
      final rawStderr = '${result['stderr'] ?? ''}';
      final stderr = cancelled && rawStderr.trim().isEmpty
          ? '钉钉 DWS 工具执行已取消。'
          : rawStderr;
      final exitCode = int.tryParse('${result['exit_code'] ?? 0}');
      final status = cancelled
          ? BashToolExecutionStatus.cancelled
          : timedOut
          ? BashToolExecutionStatus.timedOut
          : exitCode == 0
          ? BashToolExecutionStatus.success
          : BashToolExecutionStatus.failed;
      final output = stdout.trim().isNotEmpty ? stdout.trim() : stderr.trim();
      return AiToolExecutionResult(
        status: status,
        command: command.cliPath,
        workingDirectory: _workingDirectory(context),
        stdout: stdout,
        stderr: stderr,
        durationMs:
            int.tryParse('${result['duration_ms'] ?? ''}') ??
            startedAt.elapsedMilliseconds,
        exitCode: exitCode,
        resultText: cancelled
            ? 'status: cancelled\nerror: 钉钉 DWS 工具执行已取消。'
            : output.isEmpty
            ? 'DWS 命令未返回内容。'
            : output,
        isWriteCommand: command.effect != 'read',
        writeAnalysisReason: command.effect == 'read' ? '' : '钉钉 DWS 命令标记为写操作。',
        metadata: <String, Object?>{
          'tool_source': 'dingtalk_dws',
          'dingtalk_dws_cli_path': command.cliPath,
          'dingtalk_dws_product_id': command.productId,
          'dingtalk_dws_product_name': command.productName,
          'dingtalk_dws_effect': command.effect,
          'dingtalk_dws_risk': command.risk,
          'dingtalk_dws_confirmation': command.confirmation,
          'dingtalk_dws_status': status.storageValue,
          if (cancelled) 'execution_cancelled': true,
          'dingtalk_dws_duration_ms': startedAt.elapsedMilliseconds,
        },
      );
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: command.cliPath,
        workingDirectory: _workingDirectory(context),
        stdout: '',
        stderr: '$error',
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'status: failed\nerror: $error',
        isWriteCommand: command.effect != 'read',
        metadata: <String, Object?>{
          'tool_source': 'dingtalk_dws',
          'dingtalk_dws_cli_path': command.cliPath,
          'dingtalk_dws_status': 'failed',
          'dingtalk_dws_duration_ms': startedAt.elapsedMilliseconds,
        },
      );
    }
  }

  String _workingDirectory(AiToolExecutionContext context) {
    final boundary = context.metadata['dingtalk_working_directory_boundary'];
    return boundary is String && boundary.trim().isNotEmpty
        ? boundary.trim()
        : AiToolUtils.defaultWorkingDirectory();
  }

  bool _isMissing(Object? value) {
    if (value == null) return true;
    return value is String && value.trim().isEmpty;
  }

  static List<String> buildCliArguments(
    AiDingTalkDwsCommand command,
    Map<String, Object?> arguments,
  ) {
    final result = <String>[];
    for (final name in command.positionals) {
      final value = arguments[name];
      if (value == null) continue;
      final text = value is String ? value : '$value';
      if (text.trim().isNotEmpty) result.add(text);
    }
    for (final entry in arguments.entries) {
      if (command.positionals.contains(entry.key)) continue;
      final value = entry.value;
      if (value == null) continue;
      final text = value is String
          ? value
          : value is List || value is Map
          ? jsonEncode(value)
          : '$value';
      if (text.trim().isEmpty) continue;
      result
        ..add('--${entry.key}')
        ..add(text);
    }
    return result;
  }
}
