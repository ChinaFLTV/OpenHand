import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseService databaseService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_session_controller_test_',
    );
    databaseService = await DatabaseService.initialize(
      databasePath: p.join(tempDir.path, 'openhand-test.db'),
      useNoIsolateFactory: true,
    );
  });

  tearDown(() async {
    await databaseService.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('deleting current session hydrates the auto-selected session', () async {
    final store = AiSessionStore(
      sessionsDirectoryPath: p.join(tempDir.path, 'sessions'),
    );
    final now = DateTime.utc(2026, 6, 23, 10);
    final targetSession = _session(
      id: 'target-session',
      title: 'Target session',
      updatedAt: now.add(const Duration(minutes: 2)),
      messages: <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'target-message',
          content: 'Already persisted message',
          createdAt: now,
        ),
      ],
    );
    final deletedSession = _session(
      id: 'deleted-session',
      title: 'Deleted session',
      updatedAt: now.add(const Duration(minutes: 1)),
      messages: <AiSessionMessage>[
        AiSessionMessage.user(
          id: 'deleted-message',
          content: 'Delete me',
          createdAt: now,
        ),
      ],
    );
    await store.save(targetSession);
    await store.save(deletedSession);

    final controller = await AiSessionController.create(
      store: store,
      chatClient: _FakeAiChatClient(),
      backgroundChatClient: _FakeAiChatClient(),
    );
    addTearDown(controller.dispose);

    await controller.selectSession(deletedSession.id);
    await controller.ensureSessionMessageWindowHydrated(deletedSession.id);
    expect(controller.currentSessionId, deletedSession.id);

    final deleted = await controller.deleteSession(deletedSession.id);
    expect(deleted, isTrue);
    expect(controller.currentSessionId, targetSession.id);

    await _pumpUntil(
      () {
        final session = controller.sessionById(targetSession.id);
        return session != null &&
            session.messages.isNotEmpty &&
            session.messageLoadState != AiSessionMessageLoadState.header &&
            !controller.isSessionMessagesHydrating(targetSession.id);
      },
    );

    final hydratedTarget = controller.sessionById(targetSession.id);
    expect(hydratedTarget, isNotNull);
    expect(hydratedTarget!.messages.map((message) => message.id), <String>[
      'target-message',
    ]);
    expect(hydratedTarget.messageLoadState, AiSessionMessageLoadState.complete);
    expect(controller.isSessionMessagesHydrating(targetSession.id), isFalse);
  });
}

AiSession _session({
  required String id,
  required String title,
  required DateTime updatedAt,
  required List<AiSessionMessage> messages,
}) {
  return AiSession(
    id: id,
    title: title,
    templateId: 'default',
    templateName: 'Default Assistant',
    templateIconName: 'sparkles',
    templateInternalVersion: 'test',
    createdAt: updatedAt.subtract(const Duration(minutes: 5)),
    updatedAt: updatedAt,
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'en',
      platform: 'test',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '',
      homeDirectory: '',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: '',
      compressionThresholdChars: 0,
    ),
    statistics: const AiSessionStatistics.initial().copyWith(
      totalMessageCount: messages.length,
      userMessageCount: messages
          .where((message) => message.kind == AiSessionMessageKind.user)
          .length,
    ),
    recentErrors: const <AiSessionErrorRecord>[],
  );
}

Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for condition.');
}

class _FakeAiChatClient implements AiChatClient {
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
    return const AiChatCompletion(reply: 'OK');
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
    return AiChatStreamingResponse(
      events: const Stream<AiChatStreamEvent>.empty(),
      result: Future<AiChatStreamResult>.value(
        const AiChatStreamResult(reply: 'OK', reasoning: '', toolCalls: []),
      ),
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async => 'OK';

  @override
  void dispose() {}
}
