import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/index.dart';

void main() {
  group('AiToolRuntimeService retry policy', () {
    test(
      'does not retry side-effect builtin Bash even when retry is enabled',
      () async {
        final marker = File(
          '/tmp/openhand-retry-suppression-${DateTime.now().microsecondsSinceEpoch}.txt',
        );
        if (marker.existsSync()) {
          marker.deleteSync();
        }
        addTearDown(() {
          if (marker.existsSync()) marker.deleteSync();
        });

        final runtime = AiToolRuntimeService(
          bashToolService: AiBashToolService(),
          hookService: AiNoopClaudeHookService(),
          mcpToolService: _FakeMcpToolDiscoveryService(),
          backgroundChatClient: _FakeChatClient(),
        );
        const retryConfig = AiBuiltinToolConfig(
          kind: AiBuiltinToolKind.bash,
          retryOnFailure: true,
          maxRetries: 3,
          retryBackoffMs: 0,
        );
        const definition = AiToolDefinition(
          name: 'Bash',
          description: 'Run bash',
          parameters: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'cmd': <String, Object?>{'type': 'string'},
              'working_directory': <String, Object?>{'type': 'string'},
            },
            'required': <String>['cmd'],
            'additionalProperties': false,
          },
        );
        const catalog = AiResolvedToolCatalog(
          definitions: <AiToolDefinition>[definition],
          toolsByName: <String, AiResolvedTool>{
            'Bash': AiResolvedTool(
              name: 'Bash',
              definition: definition,
              source: AiRuntimeToolSource.builtin,
              builtinKind: AiBuiltinToolKind.bash,
              builtinConfig: retryConfig,
            ),
          },
        );
        final result = await runtime.execute(
          sessionId: 'runtime-retry-test',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-1',
            name: 'Bash',
            arguments: jsonEncode(<String, Object?>{
              'cmd':
                  "printf x >> '${marker.path.replaceAll("'", "'\\''")}'; false",
              'working_directory': '/tmp',
            }),
          ),
          model: _testModel,
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: null,
        );

        expect(result.status, BashToolExecutionStatus.failed);
        expect(result.exitCode, 1);
        expect(result.metadata['retry_suppressed'], isTrue);
        expect(
          result.metadata['retry_suppressed_reason'],
          'builtin_tool_may_have_side_effects',
        );
        expect(marker.readAsStringSync(), 'x');
      },
    );
  });

  group('AiToolRuntimeService unsupported tool guidance', () {
    test(
      'preserves plan gate metadata when catalog is intentionally empty',
      () async {
        final runtime = AiToolRuntimeService(
          bashToolService: AiBashToolService(),
          hookService: AiNoopClaudeHookService(),
          mcpToolService: _FakeMcpToolDiscoveryService(),
          backgroundChatClient: _FakeChatClient(),
        );

        final result = await runtime.execute(
          sessionId: 'runtime-plan-gate-test',
          catalog: const AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[],
            toolsByName: <String, AiResolvedTool>{},
          ),
          toolCall: const AiToolCall(
            id: 'call-1',
            name: 'Write',
            arguments: '{}',
          ),
          model: _testModel,
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: true,
          confirmWriteCommand: null,
          metadata: const <String, Object?>{
            'session_mode': 'plan',
            'plan_mode_active': true,
            'awaiting_plan_approval': true,
            'plan_mode_execution_approved_for_send': false,
          },
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(result.stderr, contains('waiting for the user to approve'));
        expect(result.stderr, contains('restores the execution toolkit'));
        expect(result.stderr, contains('Do not invent tool names'));
        expect(result.stderr, contains('dump code into chat'));
        expect(result.metadata['unsupported_tool_name'], 'Write');
        expect(result.metadata['tool_catalog_empty'], isTrue);
        expect(result.metadata['available_tool_names'], isEmpty);
        expect(result.metadata['plan_mode_active'], isTrue);
        expect(result.metadata['awaiting_plan_approval'], isTrue);
        expect(
          result.metadata['plan_mode_execution_approved_for_send'],
          isFalse,
        );
      },
    );
  });

  group('AiToolRuntimeService builtin schemas', () {
    test('Bash accepts Claude-style run_in_background input', () {
      final runtime = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: AiNoopClaudeHookService(),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        backgroundChatClient: _FakeChatClient(),
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _testRuntimeContext,
      );
      final definition = catalog.find('Bash')?.definition;
      final parameters = definition?.parameters;
      final properties = parameters?['properties'];

      expect(definition, isNotNull);
      expect(properties, isA<Map>());
      expect(
        (properties as Map)['run_in_background'],
        containsPair('type', 'boolean'),
      );
    });

    test('Task accepts omitted subagent type input', () {
      final runtime = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: AiNoopClaudeHookService(),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        backgroundChatClient: _FakeChatClient(),
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _testRuntimeContext,
      );
      final definition = catalog.find('Task')?.definition;
      final parameters = definition?.parameters;
      final required = parameters?['required'];

      expect(definition, isNotNull);
      if (required is List) {
        expect(required, containsAll(<String>['description', 'prompt']));
        expect(required, isNot(contains('subagent_type')));
      } else {
        fail('Task schema should require description and prompt.');
      }
    });

    test('ExitPlanMode accepts Claude-style omitted plan input', () {
      final runtime = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: AiNoopClaudeHookService(),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        backgroundChatClient: _FakeChatClient(),
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _testRuntimeContext,
      );
      final definition = catalog.find('ExitPlanMode')?.definition;
      final parameters = definition?.parameters;
      final required = parameters?['required'];

      expect(definition, isNotNull);
      if (required is List) {
        expect(required, isNot(contains('plan')));
      } else {
        expect(required, isNull);
      }
    });
  });

  group('AiToolRuntimeService Bash background alias', () {
    test('routes run_in_background to BashBackground start', () async {
      final runtime = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: AiNoopClaudeHookService(),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        backgroundChatClient: _FakeChatClient(),
      );
      addTearDown(runtime.dispose);
      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _testRuntimeContext,
      );

      final result = await runtime.execute(
        sessionId: 'runtime-bash-background-alias-test',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-bg-1',
          name: 'Bash',
          arguments: jsonEncode(<String, Object?>{
            'cmd': 'sleep 5',
            'working_directory': '/tmp',
            'run_in_background': true,
          }),
        ),
        model: _testModel,
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.command, startsWith('BashBackground start bg_'));
      expect(result.stdout, contains('status: started'));
      expect(result.stdout, contains('handle: bg_'));
      expect(result.metadata['bash_run_in_background_alias'], isTrue);
      expect(result.metadata['routed_from_tool'], 'Bash');
      expect(result.metadata['routed_to_tool'], 'BashBackground');
      expect(result.metadata['bg_handle'], isA<String>());
    });

    test(
      'rejects run_in_background when BashBackground is unavailable',
      () async {
        final runtime = AiToolRuntimeService(
          bashToolService: AiBashToolService(),
          hookService: AiNoopClaudeHookService(),
          mcpToolService: _FakeMcpToolDiscoveryService(),
          backgroundChatClient: _FakeChatClient(),
        );
        addTearDown(runtime.dispose);
        final fullCatalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _testRuntimeContext,
        );
        final bashTool = fullCatalog.find('Bash')!;
        final bashOnlyCatalog = AiResolvedToolCatalog(
          definitions: <AiToolDefinition>[bashTool.definition],
          toolsByName: <String, AiResolvedTool>{'Bash': bashTool},
        );

        final result = await runtime.execute(
          sessionId: 'runtime-bash-background-missing-test',
          catalog: bashOnlyCatalog,
          toolCall: AiToolCall(
            id: 'call-bg-2',
            name: 'Bash',
            arguments: jsonEncode(<String, Object?>{
              'cmd': 'sleep 5',
              'run_in_background': true,
            }),
          ),
          model: _testModel,
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: null,
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(result.stderr, contains('requires BashBackground'));
      },
    );
  });

  group('AiToolRuntimeService output budget', () {
    const definition = AiToolDefinition(
      name: 'Bash',
      description: 'Run bash',
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'cmd': <String, Object?>{'type': 'string'},
          'working_directory': <String, Object?>{'type': 'string'},
        },
        'required': <String>['cmd'],
        'additionalProperties': false,
      },
    );
    const catalog = AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[definition],
      toolsByName: <String, AiResolvedTool>{
        'Bash': AiResolvedTool(
          name: 'Bash',
          definition: definition,
          source: AiRuntimeToolSource.builtin,
          builtinKind: AiBuiltinToolKind.bash,
        ),
      },
    );

    Future<AiToolExecutionResult> executeLongOutput(
      AiToolRuntimeService runtime, {
      String toolCallId = 'call-1',
    }) {
      return runtime.execute(
        sessionId: 'runtime-output-budget-test',
        catalog: catalog,
        toolCall: AiToolCall(
          id: toolCallId,
          name: 'Bash',
          arguments: jsonEncode(<String, Object?>{
            'cmd':
                'python3 -c \'print("BEGIN-" + ("middle" * 200) + "-END", end="")\'',
            'working_directory': '/tmp',
          }),
        ),
        model: _testModel,
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      );
    }

    test('annotates truncated tool output with structured metadata', () async {
      final outputDir = await Directory.systemTemp.createTemp(
        'openhand-tool-output-test-',
      );
      addTearDown(() async {
        if (await outputDir.exists()) {
          await outputDir.delete(recursive: true);
        }
      });
      final runtime = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: AiNoopClaudeHookService(),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        backgroundChatClient: _FakeChatClient(),
        toolOutputDirectoryProvider: (sessionId) =>
            '${outputDir.path}/$sessionId/tool-results',
      )..maxToolOutputChars = 520;

      final result = await executeLongOutput(runtime);

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.resultText, contains('-END'));
      expect(result.resultText, contains('[Output truncated: omitted'));
      expect(result.resultText, contains('Full output saved to:'));
      expect(result.resultText.length, lessThanOrEqualTo(520));
      expect(result.stdout, contains('BEGIN-'));
      expect(result.stdout, contains('-END'));
      expect(result.stdout, contains('[Output truncated: omitted'));
      expect(result.metadata['tool_output_truncated'], isTrue);
      expect(result.metadata['tool_output_budget_chars'], 520);
      expect(result.metadata['tool_output_truncation_strategy'], 'head_tail');
      expect(result.metadata['tool_output_full_content_available'], isTrue);
      expect(
        result.metadata['tool_output_recovery_hint'],
        'read_persisted_output',
      );
      expect(result.metadata['tool_output_persisted'], isTrue);
      expect(result.metadata['tool_output_persistence_format'], 'text');
      final persistedPath =
          result.metadata['tool_output_persisted_path'] as String;
      final persistedFile = File(persistedPath);
      expect(await persistedFile.exists(), isTrue);
      final persistedContent = await persistedFile.readAsString();
      expect(persistedContent, contains('BEGIN-'));
      expect(persistedContent, contains('-END'));
      expect(
        result.metadata['tool_output_persisted_chars'],
        persistedContent.length,
      );
      final originalLength =
          result.metadata['tool_output_original_length'] as int;
      final includedChars =
          result.metadata['tool_output_included_chars'] as int;
      final omittedChars = result.metadata['tool_output_omitted_chars'] as int;
      expect(originalLength, greaterThan(320));
      expect(includedChars, greaterThan(0));
      expect(omittedChars, greaterThan(0));
      expect(includedChars + omittedChars, originalLength);
    });

    test('falls back cleanly when persisted output is unavailable', () async {
      final runtime = AiToolRuntimeService(
        bashToolService: AiBashToolService(),
        hookService: AiNoopClaudeHookService(),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        backgroundChatClient: _FakeChatClient(),
        toolOutputDirectoryProvider: (_) => '   ',
      )..maxToolOutputChars = 520;

      final result = await executeLongOutput(runtime, toolCallId: 'call-2');

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.resultText, contains('[Output truncated: omitted'));
      expect(result.resultText, contains('Full output was not persisted'));
      expect(result.resultText.length, lessThanOrEqualTo(520));
      expect(result.metadata['tool_output_truncated'], isTrue);
      expect(result.metadata['tool_output_full_content_available'], isFalse);
      expect(
        result.metadata['tool_output_recovery_hint'],
        'rerun_with_narrower_query',
      );
      expect(
        result.metadata.containsKey('tool_output_persisted_path'),
        isFalse,
      );
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

const AiSessionRuntimeContext _testRuntimeContext = AiSessionRuntimeContext(
  localeTag: 'zh-CN',
  appVersion: 'test',
  appBuildNumber: '1',
  settingsFilePath: '/tmp/settings.json',
  skillsStoragePath: '/tmp/skills',
  mcpServersFilePath: '/tmp/mcp.json',
  userMemoryFilePath: '/tmp/memory.json',
  compressionThresholdChars: 1000,
  memoryEnabled: false,
  memoryEntries: <Never>[],
  workingDirectory: '/tmp/project',
  platformName: 'macOS',
  timeZoneName: 'Asia/Shanghai',
);

class _FakeChatClient implements AiChatClient {
  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 60),
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) async {
    return const AiChatCompletion(reply: '');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 60),
    Duration streamIdleTimeout = const Duration(seconds: 60),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> testModel(AiModelConfig model) async => 'OK';

  @override
  void dispose() {}
}

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  @override
  Future<McpServerHealth> checkHealth(McpServer server) {
    throw UnimplementedError();
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
