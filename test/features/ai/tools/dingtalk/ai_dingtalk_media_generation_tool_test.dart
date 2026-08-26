import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/media/ai_image_generation_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/dingtalk/ai_dingtalk_media_generation_tool.dart';
import 'package:openhand/shared/model/dingtalk_multimodal_capability.dart';

void main() {
  group('钉钉音频生成工具', () {
    test('合并顶层与选项对象并透传不指定音色', () async {
      AiCreationOptions? capturedOptions;
      final executor = _executor((options, _) async {
        capturedOptions = options;
        return const <String, Object?>{
          'success': true,
          'file_path': '/tmp/generated.mp3',
          'file_name': 'generated.mp3',
        };
      });

      final tool = AiDingTalkMediaGenerationTool(
        AiDingTalkMultimodalCapability.audioGeneration,
      );

      final result = await tool.execute(
        _context(
          executor: executor,
          arguments: const <String, Object?>{
            'prompt': '轻快的器乐旋律',
            'voice': 'alloy',
            'omit_voice': true,
            'options': <String, Object?>{
              'sample_rate': 44100,
              'bitrate': 256000,
              'output_format': 'mp3',
            },
          },
        ),
      );

      final options = capturedOptions!;
      expect(options.omitVoice, isTrue);
      expect(options.voice, isNull);
      expect(options.sampleRate, 44100);
      expect(options.bitrate, 256000);
      expect(options.outputFormat, 'mp3');
      expect(result.status, BashToolExecutionStatus.success);
      expect(result.metadata['dingtalk_force_final_response'], isTrue);
      expect(tool.isDestructive, isTrue);
    });

    test('发送成功后到达取消信号仍按成功结束', () async {
      final cancelled = Completer<void>();
      final executor = _executor((_, _) async {
        cancelled.complete();
        return const <String, Object?>{
          'success': true,
          'file_path': '/tmp/generated.mp3',
          'file_name': 'generated.mp3',
        };
      });

      final tool = AiDingTalkMediaGenerationTool(
        AiDingTalkMultimodalCapability.audioGeneration,
      );

      final result = await tool.execute(
        _context(
          executor: executor,
          cancelSignal: cancelled.future,
          arguments: const <String, Object?>{'prompt': '生成一段音乐'},
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.metadata['dingtalk_force_final_response'], isTrue);
    });

    test('执行前已取消时不启动生成器', () async {
      var executed = false;
      final cancelled = Completer<void>()..complete();
      final executor = _executor((_, _) async {
        executed = true;
        return const <String, Object?>{'success': true};
      });

      final tool = AiDingTalkMediaGenerationTool(
        AiDingTalkMultimodalCapability.audioGeneration,
      );

      final result = await tool.execute(
        _context(
          executor: executor,
          cancelSignal: cancelled.future,
          arguments: const <String, Object?>{'prompt': '生成一段音乐'},
        ),
      );

      expect(executed, isFalse);
      expect(result.status, BashToolExecutionStatus.cancelled);
    });

    test('生成阶段取消时返回清晰的取消状态', () async {
      final executor = _executor(
        (_, _) async => throw const AiMediaGenerationCancelledException(),
      );
      final tool = AiDingTalkMediaGenerationTool(
        AiDingTalkMultimodalCapability.audioGeneration,
      );

      final result = await tool.execute(
        _context(
          executor: executor,
          arguments: const <String, Object?>{'prompt': '生成一段音乐'},
        ),
      );

      expect(result.status, BashToolExecutionStatus.cancelled);
      expect(result.resultText, '媒体生成已取消。');
      expect(result.metadata['execution_cancelled'], isTrue);
    });
  });
}

AiDingTalkMediaGenerationExecutor _executor(
  Future<Object?> Function(AiCreationOptions, Future<void>?) execute,
) {
  return ({
    required capability,
    required prompt,
    required options,
    required referenceImagePaths,
    cancelSignal,
  }) => execute(options, cancelSignal);
}

AiToolExecutionContext _context({
  required AiDingTalkMediaGenerationExecutor executor,
  required Map<String, Object?> arguments,
  Future<void>? cancelSignal,
}) {
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: const AiToolCall(
      id: 'tool-call-1',
      name: 'DingTalkAudioGenerationTool',
      arguments: '{}',
    ),
    decodedArguments: arguments,
    model: const AiModelConfig(
      id: 'test-provider',
      baseUrl: 'https://example.com/v1',
      authScheme: AiAuthScheme.bearer,
      token: 'test-token',
      modelId: 'test-model',
      protocolType: AiProtocolType.openai,
    ),
    previouslyReadFiles: const <String>{},
    denyCommandRules: const [],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
    cancelSignal: cancelSignal,
    metadata: <String, Object?>{
      'dingtalk_media_generation_executor': executor,
      'dingtalk_working_directory_boundary': '/tmp',
    },
  );
}
