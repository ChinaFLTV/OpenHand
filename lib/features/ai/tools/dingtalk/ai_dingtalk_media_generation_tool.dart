import 'dart:async';

import '../../../../shared/model/dingtalk_multimodal_capability.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_creation_mode.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/media/ai_image_generation_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

typedef AiDingTalkMediaGenerationExecutor =
    Future<Object?> Function({
      required AiDingTalkMultimodalCapability capability,
      required String prompt,
      required AiCreationOptions options,
      required List<String> referenceImagePaths,
      Future<void>? cancelSignal,
    });

/// 钉钉网关的同步媒体生成工具。
///
/// 工具本身只负责参数校验和运行时统计；模型路由、轮询、文件发送及本地
/// 会话回显由网关注入的执行器完成，避免 AI 工具层持有钉钉会话状态。
class AiDingTalkMediaGenerationTool extends AiTool {
  AiDingTalkMediaGenerationTool(this.capability);

  static const int maxPromptCharacters = 12000;
  static const int maxReferenceImages = 8;
  static const int maxReferencePathCharacters = kBytesPerKiB;

  final AiDingTalkMultimodalCapability capability;

  @override
  AiBuiltinToolKind get kind => switch (capability) {
    AiDingTalkMultimodalCapability.imageGeneration =>
      AiBuiltinToolKind.dingtalkImageGeneration,
    AiDingTalkMultimodalCapability.videoGeneration =>
      AiBuiltinToolKind.dingtalkVideoGeneration,
    AiDingTalkMultimodalCapability.audioGeneration =>
      AiBuiltinToolKind.dingtalkAudioGeneration,
  };

  @override
  bool get isDestructive => true;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final command = capability.toolName;
    final prompt = _prompt(context.decodedArguments);
    if (prompt.isEmpty) {
      return AiToolUtils.invalidResult(command, '媒体生成要求不能为空。');
    }
    if (prompt.length > maxPromptCharacters) {
      return AiToolUtils.invalidResult(
        command,
        '媒体生成要求不能超过 $maxPromptCharacters 个字符。',
      );
    }
    final executor = context.metadata['dingtalk_media_generation_executor'];
    if (executor is! AiDingTalkMediaGenerationExecutor) {
      return AiToolUtils.invalidResult(command, '钉钉多模态生成执行器不可用。');
    }
    final paths = _referenceImagePaths(context.decodedArguments);
    final options = _options(context.decodedArguments);
    if (await _isCancelled(context.cancelSignal)) {
      return _cancelled(command, 0, _workingDirectory(context));
    }
    final startedAt = Stopwatch()..start();
    try {
      final raw = await executor(
        capability: capability,
        prompt: prompt,
        options: options,
        referenceImagePaths: paths,
        cancelSignal: context.cancelSignal,
      );
      final result = raw is Map
          ? Map<String, Object?>.from(raw)
          : <String, Object?>{'message': '$raw'};
      final failed =
          result['success'] == false ||
          '${result['error'] ?? ''}'.trim().isNotEmpty;
      final filePath = '${result['file_path'] ?? ''}'.trim();
      final fileName = '${result['file_name'] ?? ''}'.trim();
      final message = failed
          ? '${result['error'] ?? '媒体生成或发送失败。'}'
          : fileName.isEmpty
          ? '已生成并发送${capability.displayName}。'
          : '已生成并发送${capability.displayName}：$fileName。';
      return AiToolExecutionResult(
        status: failed
            ? BashToolExecutionStatus.failed
            : BashToolExecutionStatus.success,
        command: command,
        workingDirectory: _workingDirectory(context),
        stdout: message,
        stderr: failed ? message : '',
        durationMs:
            int.tryParse('${result['duration_ms'] ?? ''}') ??
            startedAt.elapsedMilliseconds,
        resultText: message,
        isWriteCommand: true,
        writeAnalysisReason: '生成媒体并发送到钉钉会话。',
        metadata: <String, Object?>{
          'tool_source': 'dingtalk_media_generation',
          'dingtalk_media_capability': capability.storageValue,
          'dingtalk_media_response': !failed,
          'dingtalk_force_final_response': !failed,
          if (filePath.isNotEmpty) 'dingtalk_media_file_path': filePath,
          if (fileName.isNotEmpty) 'dingtalk_media_file_name': fileName,
          if (result['remote_message_id'] != null)
            'dingtalk_media_remote_message_id': result['remote_message_id'],
        },
      );
    } on AiMediaGenerationCancelledException {
      return _cancelled(
        command,
        startedAt.elapsedMilliseconds,
        _workingDirectory(context),
      );
    } on Object catch (error) {
      if (await _isCancelled(context.cancelSignal)) {
        return _cancelled(
          command,
          startedAt.elapsedMilliseconds,
          _workingDirectory(context),
        );
      }
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: command,
        workingDirectory: _workingDirectory(context),
        stdout: '',
        stderr: '$error',
        durationMs: startedAt.elapsedMilliseconds,
        resultText: '媒体生成失败：$error',
        isWriteCommand: true,
        writeAnalysisReason: '生成媒体并发送到钉钉会话。',
        metadata: <String, Object?>{
          'tool_source': 'dingtalk_media_generation',
          'dingtalk_media_capability': capability.storageValue,
          'dingtalk_media_response': false,
          'dingtalk_force_final_response': false,
        },
      );
    }
  }

  String _prompt(Map<String, Object?> arguments) {
    final value = '${arguments['prompt'] ?? arguments['text'] ?? ''}'.trim();
    return value;
  }

  AiCreationOptions _options(Map<String, Object?> arguments) {
    final flattened = Map<String, Object?>.from(arguments)
      ..remove('prompt')
      ..remove('text')
      ..remove('purpose')
      ..remove('reference_image_paths')
      ..remove('options');
    final nested = stringKeyedMapFromValueOrJsonText(arguments['options']);
    return AiCreationOptions.fromMetadata(<String, Object?>{
      ...flattened,
      ...nested,
    });
  }

  List<String> _referenceImagePaths(Map<String, Object?> arguments) {
    final raw = arguments['reference_image_paths'];
    final values = raw is List ? raw : const <Object?>[];
    return values
        .take(maxReferenceImages)
        .map((value) => '$value'.trim())
        .where(
          (value) =>
              value.isNotEmpty && value.length <= maxReferencePathCharacters,
        )
        .toSet()
        .toList(growable: false);
  }

  String _workingDirectory(AiToolExecutionContext context) {
    final value = context.metadata['dingtalk_working_directory_boundary'];
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : AiToolUtils.defaultWorkingDirectory();
  }

  Future<bool> _isCancelled(Future<void>? signal) async {
    return isCancelSignalCompleted(signal);
  }

  AiToolExecutionResult _cancelled(
    String command,
    int durationMs,
    String workingDirectory,
  ) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.cancelled,
      command: command,
      workingDirectory: workingDirectory,
      stdout: '',
      stderr: '媒体生成已取消。',
      durationMs: durationMs,
      resultText: '媒体生成已取消。',
      isWriteCommand: true,
      writeAnalysisReason: '生成媒体并发送到钉钉会话。',
      metadata: <String, Object?>{
        'tool_source': 'dingtalk_media_generation',
        'dingtalk_media_capability': capability.storageValue,
        'dingtalk_media_response': false,
        'dingtalk_force_final_response': false,
        'execution_cancelled': true,
      },
    );
  }
}
