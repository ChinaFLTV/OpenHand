import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/fs/ai_read_tool.dart';

void main() {
  group('AiReadTool', () {
    test('offset is interpreted as a 1-based starting line', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\nbeta\ngamma\ndelta\n');

      final result = await AiReadTool().execute(
        AiToolExecutionContext(
          sessionId: 'test-session',
          catalog: const AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[],
            toolsByName: <String, AiResolvedTool>{},
          ),
          toolCall: AiToolCall(
            id: 'read-offset',
            name: 'Read',
            arguments: jsonEncode(<String, Object?>{
              'file_path': file.path,
              'offset': 2,
              'limit': 2,
            }),
          ),
          decodedArguments: <String, Object?>{
            'file_path': file.path,
            'offset': 2,
            'limit': 2,
          },
          model: _testModel,
          previouslyReadFiles: <String>{},
          denyCommandRules: const <Never>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: null,
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains('   2\tbeta'));
      expect(result.stdout, contains('   3\tgamma'));
      expect(result.stdout, isNot(contains('alpha')));
      expect(result.stdout, isNot(contains('delta')));
    });
  });
}

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);
