import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AiSessionController fork', () {
    Directory? tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_session_controller_fork_test_',
      );
      if (DatabaseService.isInitialized) {
        await DatabaseService.instance.close();
      }
      await DatabaseService.initialize(
        databasePath: p.join(tempDir!.path, 'openhand.db'),
        useNoIsolateFactory: true,
      );
    });

    tearDown(() async {
      if (DatabaseService.isInitialized) {
        await DatabaseService.instance.close();
      }
      final dir = tempDir;
      tempDir = null;
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('copies persisted tool outputs into the forked session', () async {
      final now = DateTime.utc(2026, 6, 19, 8);
      final store = AiSessionStore(
        sessionsDirectoryPath: p.join(tempDir!.path, 'sessions'),
      );
      final sourceToolOutput = File(
        p.join(
          store.sessionToolResultsDirectoryPath('source-session'),
          'call-1.txt',
        ),
      );
      await sourceToolOutput.parent.create(recursive: true);
      await sourceToolOutput.writeAsString('complete tool output');
      final sourceMessages = <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'user-1',
          content: 'run the command',
          createdAt: now,
        ),
        AiSessionMessage.toolResult(
          id: 'tool-result-1',
          content: 'preview',
          createdAt: now.add(const Duration(seconds: 1)),
          metadata: <String, Object?>{
            'tool_call_id': 'call-1',
            'tool_name': 'Bash',
            'tool_output_persisted': true,
            'tool_output_persisted_path': sourceToolOutput.path,
            'tool_output_persisted_chars': 20,
            'tool_output_full_content_available': true,
          },
        ),
      ];
      final sourceSession = AiSession(
        id: 'source-session',
        title: 'Fork source',
        templateId: 'programming_expert',
        templateName: '编程专家',
        templateIconName: 'code_rounded',
        templateInternalVersion: 'test',
        createdAt: now,
        updatedAt: now,
        messages: sourceMessages,
        environment: _testEnvironment(tempDir!.path),
        statistics: AiSessionStatistics.fromMessages(
          sourceMessages,
          totalPromptCharacters: 0,
          promptBuildCount: 0,
          compressionRunCount: 0,
          totalUsage: const AiTokenUsage(),
          lastPromptSystemMessageCount: 0,
          lastPromptHistoryMessageCount: 0,
        ),
        recentErrors: const <AiSessionErrorRecord>[],
      );
      await store.save(sourceSession);
      final idGenerator = _QueuedIdGenerator(<String>[
        'fork-session-1',
        'fork-user-1',
        'fork-tool-result-1',
      ]);
      final chatClient = _FakeChatClient();
      final controller = await AiSessionController.create(
        store: store,
        chatClient: chatClient,
        backgroundChatClient: chatClient,
        bashToolService: AiBashToolService(),
        hookService: AiNoopClaudeHookService(),
        mcpToolService: _FakeMcpToolDiscoveryService(),
        idGenerator: idGenerator.next,
        clock: () => now.add(const Duration(minutes: 1)),
      );
      addTearDown(controller.dispose);

      final forked = await controller.forkSessionFromMessage(
        'tool-result-1',
        sessionId: 'source-session',
      );

      expect(forked, isNotNull);
      expect(forked!.id, 'fork-session-1');
      final forkedToolResult = forked.messages.singleWhere(
        (message) => message.id == 'fork-tool-result-1',
      );
      final forkedPath =
          '${forkedToolResult.metadata['tool_output_persisted_path']}';
      expect(
        forkedPath,
        p.join(
          store.sessionToolResultsDirectoryPath('fork-session-1'),
          'call-1.txt',
        ),
      );
      expect(await File(forkedPath).readAsString(), 'complete tool output');
      expect(await sourceToolOutput.exists(), isTrue);

      final loadedFork = await store.loadSession('fork-session-1');
      final loadedToolResult = loadedFork!.messages.singleWhere(
        (message) => message.id == 'fork-tool-result-1',
      );
      expect(
        loadedToolResult.metadata['tool_output_persisted_path'],
        forkedPath,
      );
    });
  });
}

AiSessionEnvironment _testEnvironment(String rootPath) {
  return AiSessionEnvironment(
    localeTag: 'zh-CN',
    platform: 'macOS',
    appVersion: 'test',
    appBuildNumber: '1',
    applicationDirectory: rootPath,
    homeDirectory: rootPath,
    settingsFilePath: p.join(rootPath, 'settings.json'),
    skillsStoragePath: p.join(rootPath, 'skills'),
    mcpServersFilePath: p.join(rootPath, 'mcp.json'),
    userMemoryFilePath: p.join(rootPath, 'memory.json'),
    sessionsDirectoryPath: p.join(rootPath, 'sessions'),
    compressionThresholdChars: 1000,
  );
}

class _QueuedIdGenerator {
  _QueuedIdGenerator(this._ids);

  final List<String> _ids;
  var _index = 0;

  String next() {
    if (_index >= _ids.length) {
      throw StateError('No queued id left for test.');
    }
    final value = _ids[_index];
    _index += 1;
    return value;
  }
}

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
