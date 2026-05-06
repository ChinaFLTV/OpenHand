import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/shared/data/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'web-originated sends reveal the user message before assistant completion',
    () async {
      await HttpOverrides.runZoned(() async {
        final temp = await Directory.systemTemp.createTemp(
          'openhand-web-sync-',
        );
        final ownsDatabase = !DatabaseService.isInitialized;
        final databaseService = await DatabaseService.initialize(
          databasePath: p.join(temp.path, 'openhand.db'),
          useNoIsolateFactory: true,
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requestSeen = Completer<void>();
        final releaseAssistantResponse = Completer<void>();
        final serverDone = Completer<void>();
        server.listen(
          (request) async {
            try {
              if (!requestSeen.isCompleted) {
                requestSeen.complete();
              }
              await utf8.decoder.bind(request).join();
              await releaseAssistantResponse.future;
              request.response
                ..statusCode = HttpStatus.internalServerError
                ..headers.contentType = ContentType.json
                ..write('{"error":"sync smoke forced failure"}');
              await request.response.close();
              if (!serverDone.isCompleted) {
                serverDone.complete();
              }
            } catch (error, stack) {
              if (!serverDone.isCompleted) {
                serverDone.completeError(error, stack);
              }
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!serverDone.isCompleted) {
              serverDone.completeError(error, stack);
            }
          },
        );
        final controller = await AiSessionController.create(
          store: AiSessionStore(
            sessionsDirectoryPath: p.join(temp.path, 'sessions'),
          ),
        );
        final runtimeContext = _runtimeContext(temp);
        final model = _delayedFailureModel(server.port);

        try {
          final created = await controller.createSession(
            templateId: 'default',
            runtimeContext: runtimeContext,
            metadata: const <String, Object?>{},
            awaitStartHook: false,
          );
          expect(created, isTrue);
          final sessionId = controller.currentSessionId;
          expect(sessionId, isNotNull);

          var sendCompleted = false;
          final sendFuture = controller
              .sendMessage(
                sessionId: sessionId,
                content: '来自 Web 的同步烟测消息',
                model: model,
                runtimeContext: runtimeContext,
                userMessageMetadata: const <String, Object?>{
                  'sent_via': 'web_api',
                },
                revealUserMessageBeforePreflight: true,
              )
              .whenComplete(() {
                sendCompleted = true;
              });

          final userMessage = await _waitForUserMessage(controller, sessionId);
          expect(sendCompleted, isFalse);
          expect(userMessage.content, '来自 Web 的同步烟测消息');
          expect(userMessage.metadata['sent_via'], 'web_api');
          final timings = userMessage.metadata['send_preflight_timings_ms'];
          expect(timings, isA<Map>());
          expect(
            (timings as Map).containsKey('persist_user_turn_metadata'),
            isTrue,
          );

          await requestSeen.future.timeout(const Duration(seconds: 2));
          releaseAssistantResponse.complete();
          final succeeded = await sendFuture.timeout(
            const Duration(seconds: 2),
          );

          expect(succeeded, isFalse);
          await serverDone.future.timeout(const Duration(seconds: 2));
          final session = controller.sessions.singleWhere(
            (item) => item.id == sessionId,
          );
          expect(session.recentErrors, isNotEmpty);
        } finally {
          controller.dispose();
          if (!releaseAssistantResponse.isCompleted) {
            releaseAssistantResponse.complete();
          }
          await server.close(force: true);
          if (ownsDatabase) {
            await databaseService.close();
          }
          await temp.delete(recursive: true);
        }
      }, createHttpClient: _createRealHttpClient);
    },
  );
}

HttpClient _createRealHttpClient(SecurityContext? context) {
  return _RealHttpOverrides().createHttpClient(context);
}

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 2);
  }
}

Future<AiSessionMessage> _waitForUserMessage(
  AiSessionController controller,
  String? sessionId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    final messages = controller.sessions
        .where((item) => item.id == sessionId)
        .expand((session) => session.messages);
    for (final message in messages) {
      if (message.kind == AiSessionMessageKind.user) {
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for the Web user message to appear in session state.',
  );
}

AiSessionRuntimeContext _runtimeContext(Directory temp) {
  return AiSessionRuntimeContext(
    localeTag: 'zh-Hans',
    appVersion: 'test',
    appBuildNumber: '1',
    settingsFilePath: p.join(temp.path, 'settings.json'),
    skillsStoragePath: p.join(temp.path, 'skills'),
    mcpServersFilePath: p.join(temp.path, 'mcp.json'),
    userMemoryFilePath: p.join(temp.path, 'memory.md'),
    compressionThresholdChars: 1000000,
    memoryEnabled: false,
    memoryEntries: const [],
    autoTitleEnabled: false,
    connectTimeoutSeconds: 1,
    responseTimeoutSeconds: 1,
    streamIdleTimeoutSeconds: 1,
    platformName: 'test',
    workingDirectory: temp.path,
    todayLocalDate: '2026-05-06',
    timeZoneName: 'UTC',
  );
}

AiModelConfig _delayedFailureModel(int port) {
  return AiModelConfig(
    id: 'sync-smoke',
    name: 'Sync smoke',
    baseUrl: 'http://127.0.0.1:$port/v1',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'sync-smoke-model',
    protocolType: AiProtocolType.openai,
    streamEnabled: false,
  );
}
