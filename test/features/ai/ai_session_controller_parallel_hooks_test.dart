import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';
import 'package:openhand/features/hooks/index.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AiSessionController parallel tool hooks', () {
    Directory? tempDir;
    late HooksController hooksController;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_parallel_hooks_test_',
      );
      if (DatabaseService.isInitialized) {
        await DatabaseService.instance.close();
      }
      await DatabaseService.initialize(
        databasePath: p.join(tempDir!.path, 'openhand.db'),
        useNoIsolateFactory: true,
      );
      hooksController = await HooksController.create();
    });

    tearDown(() async {
      hooksController.dispose();
      if (DatabaseService.isInitialized) {
        await DatabaseService.instance.close();
      }
      final dir = tempDir;
      tempDir = null;
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('runs user pre/post hooks around parallel read-only tools', () async {
      final projectDir = Directory(p.join(tempDir!.path, 'project'));
      await projectDir.create(recursive: true);
      final fileA = File(p.join(projectDir.path, 'a.txt'));
      final fileB = File(p.join(projectDir.path, 'b.txt'));
      await fileA.writeAsString('alpha\n');
      await fileB.writeAsString('beta\n');

      final chatClient = _QueuedStreamingChatClient(<AiChatStreamResult>[
        AiChatStreamResult(
          reply: '',
          reasoning: '',
          finishReason: 'tool_calls',
          toolCalls: <AiToolCall>[
            AiToolCall(
              id: 'read-a',
              name: 'Read',
              arguments: jsonEncode(<String, Object?>{'file_path': fileA.path}),
            ),
            AiToolCall(
              id: 'read-b',
              name: 'Read',
              arguments: jsonEncode(<String, Object?>{'file_path': fileB.path}),
            ),
          ],
        ),
        const AiChatStreamResult(
          reply: 'done',
          reasoning: '',
          finishReason: 'stop',
          toolCalls: <AiToolCall>[],
        ),
      ]);
      final hookExecutor = _RecordingHooksExecutor(hooksController);
      final store = AiSessionStore(
        sessionsDirectoryPath: p.join(tempDir!.path, 'sessions'),
      );
      final controller = await AiSessionController.create(
        store: store,
        chatClient: chatClient,
        backgroundChatClient: chatClient,
        templateRepository: AiPromptTemplateRepository(loader: _promptLoader),
        bashToolService: AiBashToolService(),
        hookService: AiNoopClaudeHookService(),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        userHooksExecutor: hookExecutor,
      );
      addTearDown(controller.dispose);

      final created = await controller.createSession(
        templateId: AiPromptTemplatePolicies.programmingExpertTemplateId,
        runtimeContext: _runtimeContext(projectDir.path),
        awaitStartHook: false,
      );
      expect(created, isTrue);

      final sent = await controller.sendMessage(
        content: 'Read both files.',
        model: _testModel,
        runtimeContext: _runtimeContext(projectDir.path),
        requireWriteCommandConfirmation: false,
      );

      expect(sent, isTrue);
      expect(chatClient.streamRequestCount, 2);

      final session = controller.currentSession!;
      final hookEvents = session.messages
          .map((message) => '${message.metadata['hook_event'] ?? ''}')
          .where((event) => event.isNotEmpty)
          .toList(growable: false);
      expect(
        hookEvents.where((event) => event == HookEvent.preToolUse.storageValue),
        hasLength(2),
      );
      expect(
        hookEvents.where(
          (event) => event == HookEvent.postToolUse.storageValue,
        ),
        hasLength(2),
      );
      expect(
        hookExecutor.toolCallIdsFor(HookEvent.preToolUse),
        containsAll(<String>['read-a', 'read-b']),
      );
      expect(
        hookExecutor.toolCallIdsFor(HookEvent.postToolUse),
        containsAll(<String>['read-a', 'read-b']),
      );
    });
  });
}

Future<String> _promptLoader(String assetPath) async {
  if (assetPath.endsWith('/system_instructions.md')) {
    return '<identity>test</identity>';
  }
  if (assetPath.endsWith('/developer_instructions.md')) {
    return '<runtime_catalog>test</runtime_catalog>';
  }
  if (assetPath.endsWith('/compression_summary_instructions.md')) {
    return '<role>test</role>';
  }
  return '';
}

AiSessionRuntimeContext _runtimeContext(String workingDirectory) {
  return AiSessionRuntimeContext(
    localeTag: 'zh-CN',
    appVersion: 'test',
    appBuildNumber: '1',
    settingsFilePath: p.join(workingDirectory, 'settings.json'),
    skillsStoragePath: p.join(workingDirectory, 'skills'),
    mcpServersFilePath: p.join(workingDirectory, 'mcp.json'),
    userMemoryFilePath: p.join(workingDirectory, 'memory.json'),
    compressionThresholdChars: 100000,
    memoryEnabled: false,
    memoryEntries: const <Never>[],
    workingDirectory: workingDirectory,
    platformName: 'macOS',
    timeZoneName: 'Asia/Shanghai',
    autoTitleEnabled: false,
    streamThrottleEnabled: false,
    writeCommandConfirmationEnabled: false,
    maxConcurrentTools: 2,
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

class _QueuedStreamingChatClient implements AiChatClient {
  _QueuedStreamingChatClient(List<AiChatStreamResult> results)
    : _results = List<AiChatStreamResult>.from(results);

  final List<AiChatStreamResult> _results;
  int streamRequestCount = 0;

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
    return const AiChatCompletion(reply: '<title>test</title>');
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
  }) async {
    streamRequestCount += 1;
    if (_results.isEmpty) {
      throw StateError('No queued stream result remains.');
    }
    final result = _results.removeAt(0);
    return AiChatStreamingResponse(
      events: const Stream<AiChatStreamEvent>.empty(),
      result: Future<AiChatStreamResult>.value(result),
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async => 'OK';

  @override
  void dispose() {}
}

class _RecordingHooksExecutor extends HooksExecutor {
  _RecordingHooksExecutor(HooksController controller)
    : super(controller: controller);

  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  bool hasEnabledHooksForEvent(HookEvent event) {
    return event == HookEvent.preToolUse || event == HookEvent.postToolUse;
  }

  @override
  Future<HookExecutionResult> executeEvent({
    required HookEvent event,
    required String sessionId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    payloads.add(<String, Object?>{'event': event.storageValue, ...payload});
    final toolName = '${payload['tool_name'] ?? ''}'.trim();
    final toolCallId = '${payload['tool_call_id'] ?? ''}'.trim();
    return HookExecutionResult(
      executedCount: 1,
      successCount: 1,
      hookResults: <HookEntryResult>[
        HookEntryResult(
          hookLabel: 'recording-${event.storageValue}',
          hookEvent: event,
          status: 'success',
          elapsedMs: 1,
          stdout: '${event.storageValue}:$toolName:$toolCallId',
        ),
      ],
    );
  }

  List<String> toolCallIdsFor(HookEvent event) {
    return payloads
        .where((payload) => payload['event'] == event.storageValue)
        .map((payload) => '${payload['tool_call_id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }
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
