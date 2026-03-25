import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';
import 'package:openhand/features/ai/service/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/ai_chat_service.dart';
import 'package:openhand/features/ai/service/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  late AiToolRuntimeService service;

  setUp(() {
    service = AiToolRuntimeService(
      bashToolService: AiBashToolService(),
      hookService: AiClaudeHookService(),
      mcpToolService: _FakeMcpToolDiscoveryService(),
      backgroundChatClient: _FakeChatClient(),
    );
  });

  tearDown(() {
    service.dispose();
  });

  test('AiToolRuntimeService Read renders raster image metadata', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand-read-image-',
    );
    addTearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDirectory.path}/sample.png');
    final imageBytes = img.encodePng(img.Image(width: 3, height: 2));
    await imageFile.writeAsBytes(imageBytes, flush: true);

    final result = await service.execute(
      sessionId: 'read-image',
      catalog: await service.resolveCatalog(runtimeContext: _runtimeContext()),
      toolCall: AiToolCall(
        id: 'tool-1',
        name: 'Read',
        arguments: jsonEncode(<String, Object?>{'file_path': imageFile.path}),
      ),
      model: _model(),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(result.stdout, contains('file_type: image'));
    expect(result.stdout, contains('width: 3'));
    expect(result.stdout, contains('height: 2'));
    expect(result.metadata['read_render_mode'], 'image');
  });

  test(
    'AiToolRuntimeService Read rejects relative file paths and marks empty files with a reminder',
    () async {
      final invalidResult = await service.execute(
        sessionId: 'read-relative',
        catalog: await service.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-1',
          name: 'Read',
          arguments: jsonEncode(<String, Object?>{'file_path': 'README.md'}),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(invalidResult.status, BashToolExecutionStatus.invalidArguments);
      expect(invalidResult.stderr, contains('absolute file_path'));

      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-read-empty-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final emptyFile = File('${tempDirectory.path}/empty.txt');
      await emptyFile.writeAsString('', flush: true);

      final emptyResult = await service.execute(
        sessionId: 'read-empty',
        catalog: await service.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-2',
          name: 'Read',
          arguments: jsonEncode(<String, Object?>{'file_path': emptyFile.path}),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(emptyResult.status, BashToolExecutionStatus.success);
      expect(emptyResult.metadata[aiHookSystemRemindersMetadataKey], <String>[
        'Read opened an empty file: ${emptyFile.path}',
      ]);
    },
  );

  test(
    'AiToolRuntimeService Read truncates large text file previews',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-read-large-text-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final textFile = File('${tempDirectory.path}/large.txt');
      final largeContent = List<String>.filled(
        20000,
        '0123456789abcdef',
      ).join('\n');
      await textFile.writeAsString(largeContent, flush: true);

      final result = await service.execute(
        sessionId: 'read-large-text',
        catalog: await service.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-large-text',
          name: 'Read',
          arguments: jsonEncode(<String, Object?>{'file_path': textFile.path}),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.metadata['read_truncated'], isTrue);
      expect(result.stdout, contains('   1\t0123456789abcdef'));
      expect(result.metadata[aiHookSystemRemindersMetadataKey], <String>[
        'Read truncated a large file preview: ${textFile.path}',
      ]);
    },
  );

  test(
    'AiToolRuntimeService Read renders PDF metadata instead of failing',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-read-pdf-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final pdfFile = File('${tempDirectory.path}/sample.pdf');
      await pdfFile.writeAsString(
        '%PDF-1.4\n'
        '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'
        '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'
        '3 0 obj << /Type /Page /Parent 2 0 R >> endobj\n'
        'trailer << /Root 1 0 R >>\n'
        '%%EOF\n',
        flush: true,
      );

      final result = await service.execute(
        sessionId: 'read-pdf',
        catalog: await service.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-1',
          name: 'Read',
          arguments: jsonEncode(<String, Object?>{'file_path': pdfFile.path}),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('file_type: pdf'));
      expect(result.stdout, contains('page_count_estimate: 1'));
      expect(result.metadata['read_render_mode'], 'pdf');
    },
  );

  test(
    'AiToolRuntimeService Read falls back to binary metadata for non-text files',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-read-binary-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final binaryFile = File('${tempDirectory.path}/sample.bin');
      await binaryFile.writeAsBytes(<int>[
        0x00,
        0x01,
        0x7F,
        0xFF,
        0x10,
        0x20,
        0x30,
      ], flush: true);

      final result = await service.execute(
        sessionId: 'read-binary',
        catalog: await service.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-1',
          name: 'Read',
          arguments: jsonEncode(<String, Object?>{
            'file_path': binaryFile.path,
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('file_type: binary'));
      expect(result.stdout, contains('hex_preview:'));
      expect(result.metadata['read_render_mode'], 'binary');
    },
  );

  test('AiToolRuntimeService Glob returns newer matches first', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand-glob-order-',
    );
    addTearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final olderFile = File('${tempDirectory.path}/older.md');
    final newerFile = File('${tempDirectory.path}/newer.md');
    await olderFile.writeAsString('older', flush: true);
    await newerFile.writeAsString('newer', flush: true);
    await olderFile.setLastModified(DateTime.utc(2026, 1, 1, 0, 0, 0));
    await newerFile.setLastModified(DateTime.utc(2026, 1, 2, 0, 0, 0));

    final result = await service.execute(
      sessionId: 'glob-order',
      catalog: await service.resolveCatalog(runtimeContext: _runtimeContext()),
      toolCall: AiToolCall(
        id: 'tool-1',
        name: 'Glob',
        arguments: jsonEncode(<String, Object?>{
          'pattern': '*.md',
          'path': tempDirectory.path,
        }),
      ),
      model: _model(),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(result.stdout.split('\n'), <String>[newerFile.path, olderFile.path]);
  });

  test('AiToolRuntimeService LS rejects relative directory paths', () async {
    final result = await service.execute(
      sessionId: 'ls-relative',
      catalog: await service.resolveCatalog(runtimeContext: _runtimeContext()),
      toolCall: AiToolCall(
        id: 'tool-1',
        name: 'LS',
        arguments: jsonEncode(<String, Object?>{'path': 'lib'}),
      ),
      model: _model(),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
    );

    expect(result.status, BashToolExecutionStatus.invalidArguments);
    expect(result.stderr, contains('absolute path'));
  });

  test(
    'AiToolRuntimeService WebFetch reports cross-host redirects instead of following them',
    () async {
      var requestCount = 0;
      final webFetchService = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: AiClaudeHookService(),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        backgroundChatClient: _FakeChatClient(),
        httpClient: MockClient((request) async {
          requestCount += 1;
          expect(request.url.toString(), 'https://origin.example.com/start');
          return http.Response(
            '',
            302,
            headers: <String, String>{
              'location': 'https://redirect.example.com/final',
            },
          );
        }),
      );
      addTearDown(webFetchService.dispose);

      final result = await webFetchService.execute(
        sessionId: 'webfetch-redirect',
        catalog: await webFetchService.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-1',
          name: 'WebFetch',
          arguments: jsonEncode(<String, Object?>{
            'url': 'http://origin.example.com/start',
            'prompt': 'Summarize the page.',
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(
        result.stdout,
        contains('redirect_url: https://redirect.example.com/final'),
      );
      expect(result.metadata['webfetch_redirect_cross_host'], isTrue);
      expect(requestCount, 1);
    },
  );

  test('AiToolRuntimeService WebFetch reuses cached fetch content', () async {
    var requestCount = 0;
    final webFetchService = AiToolRuntimeService(
      bashToolService: AiBashToolService(),
      hookService: AiClaudeHookService(),
      mcpToolService: _FakeMcpToolDiscoveryService(),
      backgroundChatClient: _FakeChatClient(),
      httpClient: MockClient((request) async {
        requestCount += 1;
        return http.Response(
          '<html><body>cached fetch body</body></html>',
          200,
          headers: <String, String>{'content-type': 'text/html'},
        );
      }),
    );
    addTearDown(webFetchService.dispose);
    final catalog = await webFetchService.resolveCatalog(
      runtimeContext: _runtimeContext(),
    );

    final firstResult = await webFetchService.execute(
      sessionId: 'webfetch-cache',
      catalog: catalog,
      toolCall: AiToolCall(
        id: 'tool-1',
        name: 'WebFetch',
        arguments: jsonEncode(<String, Object?>{
          'url': 'https://cache.example.com/docs',
          'prompt': 'Extract the body text.',
        }),
      ),
      model: _model(),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
    );
    final secondResult = await webFetchService.execute(
      sessionId: 'webfetch-cache',
      catalog: catalog,
      toolCall: AiToolCall(
        id: 'tool-2',
        name: 'WebFetch',
        arguments: jsonEncode(<String, Object?>{
          'url': 'https://cache.example.com/docs',
          'prompt': 'Summarize the document.',
        }),
      ),
      model: _model(),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
    );

    expect(firstResult.status, BashToolExecutionStatus.success);
    expect(secondResult.status, BashToolExecutionStatus.success);
    expect(firstResult.stdout, contains('cached fetch body'));
    expect(secondResult.stdout, contains('cached fetch body'));
    expect(secondResult.metadata['webfetch_cache_hit'], isTrue);
    expect(requestCount, 1);
  });

  test('AiToolRuntimeService Bash honors explicit timeout', () async {
    if (Platform.isWindows) {
      return;
    }
    final result = await service.execute(
      sessionId: 'bash-timeout',
      catalog: await service.resolveCatalog(runtimeContext: _runtimeContext()),
      toolCall: AiToolCall(
        id: 'tool-1',
        name: 'Bash',
        arguments: jsonEncode(<String, Object?>{
          'cmd': 'sleep 1',
          'timeout': 50,
        }),
      ),
      model: _model(),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
    );

    expect(result.status, BashToolExecutionStatus.timedOut);
  });

  test(
    'AiToolRuntimeService blocks a tool when a PreToolUse hook denies it',
    () async {
      final blockedService = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: _FakeClaudeHookService(
          preToolUseResult: const AiClaudeHookInvocationResult(
            blocked: true,
            blockReason: 'Blocked by policy hook.',
          ),
        ),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        backgroundChatClient: _FakeChatClient(),
      );
      addTearDown(blockedService.dispose);

      final result = await blockedService.execute(
        sessionId: 'hook-blocked',
        catalog: await blockedService.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-1',
          name: 'Read',
          arguments: jsonEncode(<String, Object?>{
            'file_path': '/tmp/README.md',
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(result.status, BashToolExecutionStatus.failed);
      expect(result.stderr, contains('Blocked by policy hook.'));
      expect(result.metadata['hook_blocked'], isTrue);
    },
  );

  test(
    'AiToolRuntimeService stores PostToolUse hook reminders in result metadata',
    () async {
      final hookedService = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: _FakeClaudeHookService(
          postToolUseResult: const AiClaudeHookInvocationResult(
            systemReminders: <String>['Formatter hook already ran.'],
          ),
        ),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        backgroundChatClient: _FakeChatClient(),
      );
      addTearDown(hookedService.dispose);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-hook-reminder-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final file = File('${tempDirectory.path}/README.md');
      await file.writeAsString('body', flush: true);

      final result = await hookedService.execute(
        sessionId: 'hook-reminder',
        catalog: await hookedService.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-1',
          name: 'Read',
          arguments: jsonEncode(<String, Object?>{'file_path': file.path}),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.metadata[aiHookSystemRemindersMetadataKey], <String>[
        'Formatter hook already ran.',
      ]);
    },
  );

  test(
    'AiToolRuntimeService emits PermissionRequest and Notification for write confirmation',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final hookService = _FakeClaudeHookService();
      final hookedService = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: hookService,
        mcpToolService: _FakeMcpToolDiscoveryService(),
        backgroundChatClient: _FakeChatClient(),
      );
      addTearDown(hookedService.dispose);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-permission-hook-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final targetFile = File('${tempDirectory.path}/note.txt');

      final result = await hookedService.execute(
        sessionId: 'permission-hook',
        catalog: await hookedService.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-1',
          name: 'Bash',
          arguments: jsonEncode(<String, Object?>{
            'cmd': 'printf "hello" > "${targetFile.path}"',
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: true,
        confirmWriteCommand: (_) async => true,
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(hookService.recordedEventNames, contains('PermissionRequest'));
      expect(hookService.recordedEventNames, contains('Notification'));
      expect(await targetFile.readAsString(), 'hello');
    },
  );

  test(
    'AiToolRuntimeService NotebookEdit insert requires cell_type and absolute path',
    () async {
      final relativePathResult = await service.execute(
        sessionId: 'notebook-relative',
        catalog: await service.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-1',
          name: 'NotebookEdit',
          arguments: jsonEncode(<String, Object?>{
            'notebook_path': 'notes.ipynb',
            'new_source': 'print("hi")',
            'edit_mode': 'insert',
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );
      expect(
        relativePathResult.status,
        BashToolExecutionStatus.invalidArguments,
      );
      expect(relativePathResult.stderr, contains('absolute notebook_path'));

      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-notebook-edit-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final notebookFile = File('${tempDirectory.path}/sample.ipynb');
      await notebookFile.writeAsString(
        jsonEncode(<String, Object?>{
          'cells': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'cell-1',
              'cell_type': 'code',
              'metadata': <String, Object?>{},
              'source': 'print("hello")',
            },
          ],
        }),
        flush: true,
      );

      final missingTypeResult = await service.execute(
        sessionId: 'notebook-missing-type',
        catalog: await service.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-2',
          name: 'NotebookEdit',
          arguments: jsonEncode(<String, Object?>{
            'notebook_path': notebookFile.path,
            'new_source': 'new cell',
            'edit_mode': 'insert',
          }),
        ),
        model: _model(),
        previouslyReadFiles: <String>{notebookFile.path},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(
        missingTypeResult.status,
        BashToolExecutionStatus.invalidArguments,
      );
      expect(missingTypeResult.stderr, contains('insert requires cell_type'));
    },
  );

  test(
    'AiToolRuntimeService rejects TodoWrite calls with multiple in-progress todos',
    () async {
      final result = await service.execute(
        sessionId: 'todo-invalid',
        catalog: await service.resolveCatalog(
          runtimeContext: _runtimeContext(),
        ),
        toolCall: AiToolCall(
          id: 'tool-1',
          name: 'TodoWrite',
          arguments: jsonEncode(<String, Object?>{
            'todos': <Map<String, Object?>>[
              <String, Object?>{
                'id': 't1',
                'content': 'Inspect runtime',
                'status': 'in_progress',
              },
              <String, Object?>{
                'id': 't2',
                'content': 'Patch tests',
                'status': 'in_progress',
              },
            ],
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('Only one todo may be in_progress'));
    },
  );

  test('AiToolRuntimeService Task invocations stay stateless', () async {
    if (Platform.isWindows) {
      return;
    }
    final taskService = AiToolRuntimeService(
      bashToolService: AiBashToolService(),
      hookService: AiClaudeHookService(),
      mcpToolService: _FakeMcpToolDiscoveryService(),
      backgroundChatClient: _TaskIsolationChatClient(),
    );
    addTearDown(taskService.dispose);
    final catalog = await taskService.resolveCatalog(
      runtimeContext: _runtimeContext(),
    );

    final firstTask = await taskService.execute(
      sessionId: 'task-parent',
      catalog: catalog,
      toolCall: AiToolCall(
        id: 'task-1',
        name: 'Task',
        arguments: jsonEncode(<String, Object?>{
          'description': 'set env',
          'prompt': 'Use Bash to export OPENHAND_TASK_STATE and then finish.',
          'subagent_type': 'general-purpose',
        }),
      ),
      model: _model(),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
    );
    final secondTask = await taskService.execute(
      sessionId: 'task-parent',
      catalog: catalog,
      toolCall: AiToolCall(
        id: 'task-2',
        name: 'Task',
        arguments: jsonEncode(<String, Object?>{
          'description': 'read env',
          'prompt':
              'Use Bash to print OPENHAND_TASK_STATE and return only the tool output.',
          'subagent_type': 'general-purpose',
        }),
      ),
      model: _model(),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
    );

    expect(firstTask.status, BashToolExecutionStatus.success);
    expect(secondTask.status, BashToolExecutionStatus.success);
    expect(secondTask.stdout, isNot(contains('sticky_from_task')));
    expect(secondTask.metadata['subagent_session_isolated'], isTrue);
  });
}

AiSessionRuntimeContext _runtimeContext() {
  return const AiSessionRuntimeContext(
    localeTag: 'en-US',
    appVersion: '0.1.0',
    appBuildNumber: '1',
    settingsFilePath: '/Users/example/.openhand/settings/SETTINGS.toml',
    skillsStoragePath: '/Users/example/.openhand/skills',
    mcpServersFilePath: '/Users/example/.openhand/mcp/mcp_servers.json',
    userMemoryFilePath: '/Users/example/.openhand/memory/user-memory.json',
    compressionThresholdChars: 12000,
    memoryEnabled: true,
    memoryEntries: <UserMemoryEntry>[],
  );
}

AiModelConfig _model() {
  return const AiModelConfig(
    id: 'model-1',
    baseUrl: 'https://api.example.com',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'gpt-test',
    protocolType: AiProtocolType.openai,
  );
}

class _FakeChatClient implements AiChatClient {
  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    return const AiChatCompletion(reply: '');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'ok';
  }

  @override
  void dispose() {}
}

class _FakeClaudeHookService extends AiClaudeHookService {
  _FakeClaudeHookService({
    this.preToolUseResult = const AiClaudeHookInvocationResult(),
    this.postToolUseResult = const AiClaudeHookInvocationResult(),
  });

  final AiClaudeHookInvocationResult preToolUseResult;
  final AiClaudeHookInvocationResult postToolUseResult;
  final List<String> recordedEventNames = <String>[];

  @override
  Future<AiClaudeHookInvocationResult> runHooks({
    required String eventName,
    required String sessionId,
    required Map<String, Object?> payload,
    String? matcherValue,
    String? cwd,
  }) async {
    recordedEventNames.add(eventName);
    return switch (eventName) {
      'PreToolUse' => preToolUseResult,
      'PostToolUse' => postToolUseResult,
      _ => const AiClaudeHookInvocationResult(),
    };
  }
}

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    return const McpToolCatalog(
      status: McpToolCatalogStatus.ready,
      tools: <McpTool>[],
    );
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return const McpServerHealth(status: McpServerHealthStatus.healthy);
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    return const McpToolCallResult(outputText: '');
  }

  @override
  void dispose() {}
}

class _TaskIsolationChatClient implements AiChatClient {
  int _messageCount = 0;

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    _messageCount += 1;
    return switch (_messageCount) {
      1 => AiChatCompletion(
        reply: '',
        toolCalls: <AiToolCall>[
          AiToolCall(
            id: 'sub-bash-1',
            name: 'Bash',
            arguments: jsonEncode(<String, Object?>{
              'cmd': 'export OPENHAND_TASK_STATE=sticky_from_task',
            }),
          ),
        ],
      ),
      2 => const AiChatCompletion(reply: 'set complete'),
      3 => AiChatCompletion(
        reply: '',
        toolCalls: <AiToolCall>[
          AiToolCall(
            id: 'sub-bash-2',
            name: 'Bash',
            arguments: jsonEncode(<String, Object?>{
              'cmd': r'printf %s "$OPENHAND_TASK_STATE"',
            }),
          ),
        ],
      ),
      4 => AiChatCompletion(
        reply: messages.isEmpty ? '' : messages.last.content.trim(),
      ),
      _ => const AiChatCompletion(reply: ''),
    };
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    return 'ok';
  }

  @override
  void dispose() {}
}
