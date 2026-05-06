import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_info.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/crons/crons_controller.dart';
import 'package:openhand/features/instructions/instructions_controller.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/memory/memory_controller.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';
import 'package:openhand/features/message_gateway/service/web_message_platform_service.dart';
import 'package:openhand/features/skills/skills_controller.dart';
import 'package:openhand/shared/data/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'streams controller snapshots through the real Web SSE endpoint',
    () async {
      await HttpOverrides.runZoned(() async {
        const deviceId = 'sse-smoke-device';
        final temp = await Directory.systemTemp.createTemp('openhand-web-sse-');
        final ownsDatabase = !DatabaseService.isInitialized;
        final databaseService = await DatabaseService.initialize(
          databasePath: p.join(temp.path, 'openhand.db'),
          useNoIsolateFactory: true,
        );
        final assistantServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final assistantRequestSeen = Completer<void>();
        final releaseAssistantResponse = Completer<void>();
        final assistantServerDone = Completer<void>();
        assistantServer.listen(
          (request) async {
            try {
              if (!assistantRequestSeen.isCompleted) {
                assistantRequestSeen.complete();
              }
              await utf8.decoder.bind(request).join();
              await releaseAssistantResponse.future;
              request.response
                ..statusCode = HttpStatus.internalServerError
                ..headers.contentType = ContentType.json
                ..write('{"error":"sse smoke forced failure"}');
              await request.response.close();
              if (!assistantServerDone.isCompleted) {
                assistantServerDone.complete();
              }
            } catch (error, stack) {
              if (!assistantServerDone.isCompleted) {
                assistantServerDone.completeError(error, stack);
              }
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!assistantServerDone.isCompleted) {
              assistantServerDone.completeError(error, stack);
            }
          },
        );

        final sessionController = await AiSessionController.create(
          store: AiSessionStore(
            sessionsDirectoryPath: p.join(temp.path, 'sessions'),
          ),
        );
        final settingsController = await SettingsController.create(
          store: _InMemorySettingsStore(),
        );
        final service = WebMessagePlatformService(
          sessionController: sessionController,
          settingsController: settingsController,
          skillsController: SkillsController.uninitialized(
            initialStoragePath: p.join(temp.path, 'skills'),
          ),
          mcpController: McpController.uninitialized(
            initialFilePath: p.join(temp.path, 'mcp.json'),
          ),
          memoryController: MemoryController.uninitialized(),
          cronsController: CronsController.uninitialized(),
          instructionsController: InstructionsController.uninitialized(),
          appInfo: AppInfo.fallback(),
          cacheDirectoryPath: p.join(temp.path, 'cache'),
          logsDirectoryPath: p.join(temp.path, 'logs'),
          workspaceDirectoryPath: temp.path,
        );
        final sseClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        _SseEventReader? sseReader;

        try {
          final runtimeContext = _runtimeContext(temp);
          final created = await sessionController.createSession(
            templateId: 'default',
            runtimeContext: runtimeContext,
            metadata: const WebGatewaySessionMetadata(
              loginSource: WebGatewayLoginSource.webPc,
              deviceId: deviceId,
            ).wrapForSession(),
            awaitStartHook: false,
          );
          expect(created, isTrue);
          final sessionId = sessionController.currentSessionId;
          expect(sessionId, isNotNull);

          await service.start(
            WebMessagePlatformConfig(
              enabled: true,
              listenHost: InternetAddress.loopbackIPv4.address,
              listenPort: 0,
            ),
          );

          final sseUri = Uri.parse(service.boundUrl).replace(
            path: '/api/sessions/$sessionId/events',
            queryParameters: const <String, String>{
              'device_id': deviceId,
              'source': 'WEB_PC',
            },
          );
          final sseRequest = await sseClient.getUrl(sseUri);
          sseRequest.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
          final sseResponse = await sseRequest.close().timeout(
            const Duration(seconds: 2),
          );
          expect(sseResponse.statusCode, HttpStatus.ok);
          expect(
            sseResponse.headers.contentType?.mimeType,
            'text/event-stream',
          );
          sseReader = _SseEventReader(sseResponse);

          final initialSnapshot = await _nextSnapshot(sseReader);
          expect(initialSnapshot['send_phase'], 'idle');
          expect(initialSnapshot['messages'], isEmpty);

          var sendCompleted = false;
          final sendFuture = sessionController
              .sendMessage(
                sessionId: sessionId,
                content: '通过真实 SSE 链路同步的 Web 消息',
                model: _delayedFailureModel(assistantServer.port),
                runtimeContext: runtimeContext,
                userMessageMetadata: const <String, Object?>{
                  'sent_via': 'web_api',
                },
                revealUserMessageBeforePreflight: true,
              )
              .whenComplete(() {
                sendCompleted = true;
              });

          final userSnapshot = await _waitForSnapshot(
            sseReader,
            (snapshot) => _snapshotContainsMessage(
              snapshot,
              kind: 'user',
              content: '通过真实 SSE 链路同步的 Web 消息',
            ),
          );
          expect(sendCompleted, isFalse);
          expect(userSnapshot['can_stop'], isTrue);
          expect(
            _messageMetadata(
              userSnapshot,
              '通过真实 SSE 链路同步的 Web 消息',
            )?['sent_via'],
            'web_api',
          );

          await assistantRequestSeen.future.timeout(const Duration(seconds: 2));
          releaseAssistantResponse.complete();
          final succeeded = await sendFuture.timeout(
            const Duration(seconds: 2),
          );
          expect(succeeded, isFalse);
          await assistantServerDone.future.timeout(const Duration(seconds: 2));
        } finally {
          await sseReader?.cancel();
          sseClient.close(force: true);
          await service.dispose();
          sessionController.dispose();
          settingsController.dispose();
          if (!releaseAssistantResponse.isCompleted) {
            releaseAssistantResponse.complete();
          }
          await assistantServer.close(force: true);
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

class _SseEvent {
  const _SseEvent({required this.event, required this.data});

  final String event;
  final String data;
}

class _SseEventReader {
  _SseEventReader(Stream<List<int>> stream)
    : _iterator = StreamIterator<String>(utf8.decoder.bind(stream));

  final StreamIterator<String> _iterator;
  String _buffer = '';

  Future<_SseEvent> next() {
    return _next().timeout(const Duration(seconds: 3));
  }

  Future<void> cancel() => _iterator.cancel();

  Future<_SseEvent> _next() async {
    while (true) {
      final delimiter = _buffer.indexOf('\n\n');
      if (delimiter >= 0) {
        final frame = _buffer.substring(0, delimiter);
        _buffer = _buffer.substring(delimiter + 2);
        final event = _parseFrame(frame);
        if (event != null) return event;
        continue;
      }
      if (!await _iterator.moveNext()) {
        throw StateError('SSE stream closed before the next event.');
      }
      _buffer += _iterator.current.replaceAll('\r\n', '\n');
    }
  }

  _SseEvent? _parseFrame(String frame) {
    var event = 'message';
    final dataLines = <String>[];
    for (final line in frame.split('\n')) {
      if (line.isEmpty || line.startsWith(':')) continue;
      if (line.startsWith('event:')) {
        event = line.substring('event:'.length).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring('data:'.length).trimLeft());
      }
    }
    if (dataLines.isEmpty) return null;
    return _SseEvent(event: event, data: dataLines.join('\n'));
  }
}

Future<Map<String, Object?>> _nextSnapshot(_SseEventReader reader) {
  return _waitForSnapshot(reader, (_) => true);
}

Future<Map<String, Object?>> _waitForSnapshot(
  _SseEventReader reader,
  bool Function(Map<String, Object?> snapshot) predicate,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    final event = await reader.next();
    if (event.event != 'snapshot') continue;
    final decoded = jsonDecode(event.data);
    if (decoded is! Map) continue;
    final snapshot = Map<String, Object?>.from(decoded);
    if (predicate(snapshot)) return snapshot;
  }
  fail('Timed out waiting for the expected SSE snapshot.');
}

bool _snapshotContainsMessage(
  Map<String, Object?> snapshot, {
  required String kind,
  required String content,
}) {
  return _messages(
    snapshot,
  ).any((message) => message['kind'] == kind && message['content'] == content);
}

Map<String, Object?>? _messageMetadata(
  Map<String, Object?> snapshot,
  String content,
) {
  for (final message in _messages(snapshot)) {
    if (message['content'] != content) continue;
    final metadata = message['metadata'];
    if (metadata is Map) return Map<String, Object?>.from(metadata);
  }
  return null;
}

List<Map<String, Object?>> _messages(Map<String, Object?> snapshot) {
  final raw = snapshot['messages'];
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
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
    id: 'sse-smoke',
    name: 'SSE smoke',
    baseUrl: 'http://127.0.0.1:$port/v1',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'sse-smoke-model',
    protocolType: AiProtocolType.openai,
    streamEnabled: false,
  );
}

class _InMemorySettingsStore extends SettingsStore {
  AppSettingsSnapshot _snapshot = AppSettingsSnapshot.defaults();

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: _snapshot);
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}
