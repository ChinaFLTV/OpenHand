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
    test(
      'resolves relative notebook paths from the working directory',
      () async {
        final originalWorkingDirectory = Directory.current.path;
        final tempDir = await Directory.systemTemp.createTemp(
          'openhand_notebook_edit_tool_test_',
        );
        addTearDown(() async {
          Directory.current = originalWorkingDirectory;
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        Directory.current = tempDir.path;

        final notebookPath = AiToolUtils.resolvePath('sample.ipynb');
        final notebook = File(notebookPath);
        await notebook.writeAsString(
          const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'cells': <Object?>[
              <String, Object?>{
                'cell_type': 'code',
                'id': 'cell-1',
                'metadata': <String, Object?>{},
                'source': 'print(1)\n',
              },
            ],
            'metadata': <String, Object?>{},
            'nbformat': 4,
            'nbformat_minor': 5,
          }),
        );

        final result = await AiNotebookEditTool().execute(
          _context(
            id: 'notebook-relative',
            arguments: <String, Object?>{
              'notebook_path': 'sample.ipynb',
              'cell_id': 'cell-1',
              'new_source': 'print(2)\n',
            },
            previouslyReadFiles: <String>{notebookPath},
          ),
        );

        final updated = jsonDecode(await notebook.readAsString()) as Map;
        final cells = updated['cells'] as List;

        expect(result.status.storageValue, 'success');
        expect(result.metadata['file_mutation_path'], notebookPath);
        expect((cells.single as Map)['source'], 'print(2)\n');
      },
    );

    test('rejects non-ipynb targets before editing JSON content', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_notebook_edit_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final notNotebook = File('${tempDir.path}/sample.json');
      final originalContent = const JsonEncoder.withIndent('  ').convert(
        <String, Object?>{
          'cells': <Object?>[
            <String, Object?>{
              'cell_type': 'code',
              'id': 'cell-1',
              'metadata': <String, Object?>{},
              'source': 'print(1)\n',
            },
          ],
        },
      );
      await notNotebook.writeAsString(originalContent);

      final result = await AiNotebookEditTool().execute(
        _context(
          id: 'notebook-non-ipynb',
          arguments: <String, Object?>{
            'notebook_path': notNotebook.path,
            'cell_id': 'cell-1',
            'new_source': 'print(2)\n',
          },
          previouslyReadFiles: <String>{notNotebook.path},
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('.ipynb'));
      expect(await notNotebook.readAsString(), originalContent);
    });

    test('suggests a similar notebook path when target is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_notebook_edit_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sibling = File('${tempDir.path}/analysis-copy.ipynb');
      await sibling.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'cells': <Object?>[],
          'metadata': <String, Object?>{},
          'nbformat': 4,
          'nbformat_minor': 5,
        }),
      );
      final missingPath = '${tempDir.path}/analysis.ipynb';

      final result = await AiNotebookEditTool().execute(
        _context(
          id: 'notebook-missing-suggestion',
          arguments: <String, Object?>{
            'notebook_path': missingPath,
            'cell_id': 'cell-1',
            'new_source': 'print(2)\n',
          },
          previouslyReadFiles: <String>{missingPath},
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('Notebook does not exist: $missingPath'));
      expect(result.stderr, contains('Did you mean ${sibling.path}?'));
    });

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
      final oversizedSource = _oversizedGeneratedText();

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
              'new_source': oversizedSource,
            }),
          ),
          decodedArguments: <String, Object?>{
            'notebook_path': notebook.path,
            'cell_id': 'remove',
            'edit_mode': 'delete',
            'new_source': oversizedSource,
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

    test('rejects oversized generated source for replace', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_notebook_edit_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final notebook = File('${tempDir.path}/sample.ipynb');
      final originalContent = const JsonEncoder.withIndent('  ').convert(
        <String, Object?>{
          'cells': <Object?>[
            <String, Object?>{
              'cell_type': 'code',
              'id': 'cell-1',
              'metadata': <String, Object?>{},
              'source': 'print(1)\n',
            },
          ],
          'metadata': <String, Object?>{},
          'nbformat': 4,
          'nbformat_minor': 5,
        },
      );
      await notebook.writeAsString(originalContent);

      final oversizedSource = _oversizedGeneratedText();
      final result = await AiNotebookEditTool().execute(
        AiToolExecutionContext(
          sessionId: 'test-session',
          catalog: const AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[],
            toolsByName: <String, AiResolvedTool>{},
          ),
          toolCall: AiToolCall(
            id: 'notebook-oversized-source',
            name: 'NotebookEdit',
            arguments: jsonEncode(<String, Object?>{
              'notebook_path': notebook.path,
              'cell_id': 'cell-1',
              'new_source': oversizedSource,
            }),
          ),
          decodedArguments: <String, Object?>{
            'notebook_path': notebook.path,
            'cell_id': 'cell-1',
            'new_source': oversizedSource,
          },
          model: _testModel,
          previouslyReadFiles: <String>{notebook.path},
          denyCommandRules: const <Never>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: null,
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(
        result.stderr,
        contains('new_source exceeds the maximum allowed size'),
      );
      expect(await notebook.readAsString(), originalContent);
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

String _oversizedGeneratedText() =>
    ''.padRight(AiToolUtils.maxGeneratedTextPayloadCharacters + 1, 'x');

AiToolExecutionContext _context({
  required String id,
  required Map<String, Object?> arguments,
  required Set<String> previouslyReadFiles,
}) {
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: id,
      name: 'NotebookEdit',
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _testModel,
    previouslyReadFiles: previouslyReadFiles,
    denyCommandRules: const <Never>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
  );
}

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);
