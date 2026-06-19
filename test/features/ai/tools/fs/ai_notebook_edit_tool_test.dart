import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/ai_tool_utils.dart';
import 'package:openhand/features/ai/tools/fs/ai_notebook_edit_tool.dart';

void main() {
  group('AiNotebookEditTool', () {
    test('delete mode does not require new_source', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_notebook_edit_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final notebook = File('${tempDir.path}/sample.ipynb');
      await notebook.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'cells': <Object?>[
            <String, Object?>{
              'cell_type': 'code',
              'id': 'keep',
              'metadata': <String, Object?>{},
              'source': 'print(1)\n',
            },
            <String, Object?>{
              'cell_type': 'markdown',
              'id': 'remove',
              'metadata': <String, Object?>{},
              'source': 'remove me\n',
            },
          ],
          'metadata': <String, Object?>{},
          'nbformat': 4,
          'nbformat_minor': 5,
        }),
      );

      final result = await AiNotebookEditTool().execute(
        AiToolExecutionContext(
          sessionId: 'test-session',
          catalog: const AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[],
            toolsByName: <String, AiResolvedTool>{},
          ),
          toolCall: AiToolCall(
            id: 'notebook-delete',
            name: 'NotebookEdit',
            arguments: jsonEncode(<String, Object?>{
              'notebook_path': notebook.path,
              'cell_id': 'remove',
              'edit_mode': 'delete',
            }),
          ),
          decodedArguments: <String, Object?>{
            'notebook_path': notebook.path,
            'cell_id': 'remove',
            'edit_mode': 'delete',
          },
          model: _testModel,
          previouslyReadFiles: <String>{notebook.path},
          denyCommandRules: const <Never>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: null,
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(
        result.metadata,
        isNot(contains('file_mutation_new_source_char_count')),
      );
      final updated = jsonDecode(await notebook.readAsString());
      final cells = (updated as Map<String, Object?>)['cells'] as List;
      expect(cells, hasLength(1));
      expect((cells.single as Map)['id'], 'keep');
    });

    test('rejects oversized notebooks before reading content', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_notebook_edit_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final notebook = File('${tempDir.path}/large.ipynb');
      await notebook.create();
      final handle = await notebook.open(mode: FileMode.write);
      try {
        await handle.truncate(AiToolUtils.maxEditableTextFileBytes + 1);
      } finally {
        await handle.close();
      }

      final result = await AiNotebookEditTool().execute(
        AiToolExecutionContext(
          sessionId: 'test-session',
          catalog: const AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[],
            toolsByName: <String, AiResolvedTool>{},
          ),
          toolCall: AiToolCall(
            id: 'notebook-large',
            name: 'NotebookEdit',
            arguments: jsonEncode(<String, Object?>{
              'notebook_path': notebook.path,
              'cell_id': 'cell-1',
              'new_source': 'print(1)\n',
            }),
          ),
          decodedArguments: <String, Object?>{
            'notebook_path': notebook.path,
            'cell_id': 'cell-1',
            'new_source': 'print(1)\n',
          },
          model: _testModel,
          previouslyReadFiles: <String>{notebook.path},
          denyCommandRules: const <Never>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: null,
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('File is too large to edit'));
      expect(await notebook.length(), AiToolUtils.maxEditableTextFileBytes + 1);
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
