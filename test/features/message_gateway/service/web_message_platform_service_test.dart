import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_info.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/ai_attachment_service.dart';
import 'package:openhand/features/ai/service/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/ai_chat_service.dart';
import 'package:openhand/features/ai/service/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';
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

  late Directory tempDir;
  late _ServiceHarness harness;

  setUp(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_web_gateway_service_test_',
    );
    await DatabaseService.initialize(
      databasePath: p.join(tempDir.path, 'openhand.db'),
      useNoIsolateFactory: true,
    );
    harness = await _ServiceHarness.create(tempDir);
  });

  tearDown(() async {
    await harness.dispose();
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('serves health meta cleanup and session policy over HTTP', () async {
    await harness.service.start(
      const WebMessagePlatformConfig(
        enabled: true,
        listenHost: '127.0.0.1',
        listenPort: 0,
        opsEnabled: true,
        sessionManagementEnabled: false,
        uploadCacheMaxBytes: 1024 * 1024,
      ),
    );
    final base = Uri.parse('${harness.service.boundUrl}/');

    final health = await _requestJson(base.resolve('/api/health'));
    expect(health.statusCode, HttpStatus.ok);
    expect(health.json['status'], 'ok');

    final meta = await _requestJson(base.resolve('/api/meta'));
    expect(meta.statusCode, HttpStatus.ok);
    expect(
      (meta.json['service']
          as Map<String, Object?>)['session_management_enabled'],
      isFalse,
    );

    final uploadDir = Directory(
      p.join(tempDir.path, 'cache', 'message_gateway', 'uploads', 'session-1'),
    );
    await uploadDir.create(recursive: true);
    await File(
      p.join(uploadDir.path, 'old.bin'),
    ).writeAsBytes(List<int>.filled(700 * 1024, 65));
    await File(
      p.join(uploadDir.path, 'new.bin'),
    ).writeAsBytes(List<int>.filled(700 * 1024, 66));

    final cleanup = await _requestJson(
      base.resolve('/api/ops/cleanup'),
      method: 'POST',
      body: <String, Object?>{'target': 'uploads', 'expired_only': true},
    );
    expect(cleanup.statusCode, HttpStatus.ok);
    expect(cleanup.json['target'], 'uploads');
    expect(cleanup.json['deleted_files'], greaterThanOrEqualTo(1));

    final history = await _requestJson(
      base.resolve('/api/ops/cleanup/history'),
    );
    expect(history.statusCode, HttpStatus.ok);
    expect(history.json['total'], greaterThanOrEqualTo(1));
    final historyItems = history.json['items'] as List<Object?>;
    expect((historyItems.first as Map<String, Object?>)['target'], 'uploads');

    final export = await _requestJson(base.resolve('/api/logs/export'));
    expect(export.statusCode, HttpStatus.ok);
    expect(export.json['service'], webMessagePlatformBuiltinName);
    expect(export.json['memory_logs'], isA<List<Object?>>());

    final clearUploads = await _requestJson(
      base.resolve('/api/ops/cleanup'),
      method: 'POST',
      body: <String, Object?>{'target': 'uploads'},
    );
    expect(clearUploads.statusCode, HttpStatus.ok);
    expect(clearUploads.json['target'], 'uploads');
    expect(await uploadDir.exists(), isFalse);

    final rename = await _requestJson(
      base.resolve('/api/sessions/missing'),
      method: 'PATCH',
      body: <String, Object?>{'title': 'Next'},
    );
    expect(rename.statusCode, HttpStatus.forbidden);
    expect(rename.json['error'], 'session_management_disabled');
  });

  test(
    'reads and writes workspace files inside the sandbox over HTTP',
    () async {
      await harness.service.start(
        const WebMessagePlatformConfig(
          enabled: true,
          listenHost: '127.0.0.1',
          listenPort: 0,
          workspaceFileMaxBytes: 4096,
          workspaceFileAllowedExtensions: <String>['.txt'],
        ),
      );
      final base = Uri.parse('${harness.service.boundUrl}/');

      final write = await _requestJson(
        base.resolve('/api/workspace/file'),
        method: 'PUT',
        body: <String, Object?>{'path': 'notes/hello.txt', 'content': 'hello'},
      );
      expect(write.statusCode, HttpStatus.ok);
      expect(write.json['path'], 'notes/hello.txt');

      final read = await _requestJson(
        base.resolve('/api/workspace/file?path=notes%2Fhello.txt'),
      );
      expect(read.statusCode, HttpStatus.ok);
      expect(read.json['content'], 'hello');

      final list = await _requestJson(
        base.resolve('/api/workspace/files?path=notes&type=file&q=hello'),
      );
      expect(list.statusCode, HttpStatus.ok);
      final items = list.json['items'] as List<Object?>;
      expect(items, hasLength(1));

      final disallowedExtension = await _requestJson(
        base.resolve('/api/workspace/file'),
        method: 'PUT',
        body: <String, Object?>{'path': 'notes/hello.md', 'content': 'hello'},
      );
      expect(disallowedExtension.statusCode, HttpStatus.forbidden);
      expect(disallowedExtension.json['error'], 'file_extension_not_allowed');

      final outside = await _requestJson(
        base.resolve('/api/workspace/file'),
        method: 'PUT',
        body: <String, Object?>{'path': '../escape.txt', 'content': 'nope'},
      );
      expect(outside.statusCode, HttpStatus.badRequest);
      expect(outside.json['error'], 'path_outside_workspace');
    },
  );

  test('creates renames and deletes sessions over HTTP', () async {
    await harness.service.start(
      const WebMessagePlatformConfig(
        enabled: true,
        listenHost: '127.0.0.1',
        listenPort: 0,
      ),
    );
    final base = Uri.parse('${harness.service.boundUrl}/');

    final created = await _requestJson(
      base.resolve('/api/sessions'),
      method: 'POST',
      body: <String, Object?>{
        'title': 'Original title',
        'template_id': 'default',
      },
    );
    expect(created.statusCode, HttpStatus.created);
    final session = created.json['session'] as Map<String, Object?>;
    final sessionId = session['id'] as String;
    expect(session['title'], 'Original title');

    final listed = await _requestJson(base.resolve('/api/sessions'));
    expect(listed.statusCode, HttpStatus.ok);
    expect(listed.json['total'], 1);

    final renamed = await _requestJson(
      base.resolve('/api/sessions/$sessionId'),
      method: 'PATCH',
      body: <String, Object?>{'title': 'Renamed title'},
    );
    expect(renamed.statusCode, HttpStatus.ok);
    expect(
      (renamed.json['session'] as Map<String, Object?>)['title'],
      'Renamed title',
    );

    final deleted = await _requestJson(
      base.resolve('/api/sessions/$sessionId'),
      method: 'DELETE',
    );
    expect(deleted.statusCode, HttpStatus.ok);
    expect(deleted.json['deleted_session_id'], sessionId);

    final missing = await _requestJson(
      base.resolve('/api/sessions/$sessionId'),
    );
    expect(missing.statusCode, HttpStatus.notFound);
  });
}

class _ServiceHarness {
  _ServiceHarness({
    required this.service,
    required this.sessionController,
    required this.settingsController,
    required this.skillsController,
    required this.mcpController,
    required this.memoryController,
    required this.instructionsController,
    required this.chatClient,
  });

  final WebMessagePlatformService service;
  final AiSessionController sessionController;
  final SettingsController settingsController;
  final SkillsController skillsController;
  final McpController mcpController;
  final MemoryController memoryController;
  final InstructionsController instructionsController;
  final _FakeAiChatClient chatClient;

  static Future<_ServiceHarness> create(Directory tempDir) async {
    final chatClient = _FakeAiChatClient();
    final sessionController = await AiSessionController.create(
      store: AiSessionStore(
        sessionsDirectoryPath: p.join(tempDir.path, 'sessions'),
      ),
      chatClient: chatClient,
      backgroundChatClient: chatClient,
      templateRepository: AiPromptTemplateRepository(loader: (_) async => ''),
      bashToolService: AiBashToolService(),
      hookService: AiNoopClaudeHookService(),
      attachmentService: AiAttachmentService(
        attachmentsDirectoryPath: p.join(tempDir.path, 'attachments'),
      ),
      idGenerator: () => 'id-${DateTime.now().microsecondsSinceEpoch}',
      clock: () => DateTime.now().toUtc(),
    );
    final settingsController = await SettingsController.create(
      store: SettingsStore(),
    );
    final skillsController = SkillsController.uninitialized(
      initialStoragePath: p.join(tempDir.path, 'skills'),
    );
    final mcpController = McpController.uninitialized(
      initialFilePath: p.join(tempDir.path, 'mcp_servers.json'),
    );
    final memoryController = MemoryController.uninitialized();
    final instructionsController = InstructionsController.uninitialized();
    final service = WebMessagePlatformService(
      sessionController: sessionController,
      settingsController: settingsController,
      skillsController: skillsController,
      mcpController: mcpController,
      memoryController: memoryController,
      instructionsController: instructionsController,
      appInfo: AppInfo.fallback(),
      cacheDirectoryPath: p.join(tempDir.path, 'cache'),
      logsDirectoryPath: p.join(tempDir.path, 'logs'),
      workspaceDirectoryPath: p.join(tempDir.path, 'workspace'),
    );
    return _ServiceHarness(
      service: service,
      sessionController: sessionController,
      settingsController: settingsController,
      skillsController: skillsController,
      mcpController: mcpController,
      memoryController: memoryController,
      instructionsController: instructionsController,
      chatClient: chatClient,
    );
  }

  Future<void> dispose() async {
    await service.dispose();
    sessionController.dispose();
    settingsController.dispose();
    skillsController.dispose();
    mcpController.dispose();
    memoryController.dispose();
    instructionsController.dispose();
    chatClient.dispose();
  }
}

class _HttpJsonResponse {
  const _HttpJsonResponse({required this.statusCode, required this.json});

  final int statusCode;
  final Map<String, Object?> json;
}

Future<_HttpJsonResponse> _requestJson(
  Uri uri, {
  String method = 'GET',
  Map<String, Object?>? body,
}) async {
  final payload = body == null ? '' : jsonEncode(body);
  final target = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  final socket = await Socket.connect(uri.host, uri.port);
  socket.write('$method $target HTTP/1.1\r\n');
  socket.write('Host: ${uri.host}:${uri.port}\r\n');
  socket.write('Connection: close\r\n');
  socket.write('Content-Type: ${ContentType.json.mimeType}\r\n');
  socket.write('Content-Length: ${utf8.encode(payload).length}\r\n');
  socket.write('x-openhand-device-id: test-device\r\n');
  socket.write('x-openhand-source: WEB_PC\r\n');
  socket.write('\r\n');
  if (payload.isNotEmpty) socket.write(payload);
  await socket.flush();
  final bytes = <int>[];
  await for (final chunk in socket) {
    bytes.addAll(chunk);
  }
  final text = utf8.decode(bytes);
  final headerEnd = text.indexOf('\r\n\r\n');
  final headerText = headerEnd >= 0 ? text.substring(0, headerEnd) : text;
  final bodyText = headerEnd >= 0 ? text.substring(headerEnd + 4) : '';
  final statusLine = headerText.split('\r\n').first;
  final parts = statusLine.split(' ');
  final decoded = bodyText.trim().isEmpty
      ? <String, Object?>{}
      : Map<String, Object?>.from(jsonDecode(bodyText) as Map);
  return _HttpJsonResponse(statusCode: int.parse(parts[1]), json: decoded);
}

class _FakeAiChatClient implements AiChatClient {
  bool disposed = false;

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 1),
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) async {
    return const AiChatCompletion(reply: 'ok');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 1),
    Duration streamIdleTimeout = const Duration(seconds: 1),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) async {
    return AiChatStreamingResponse(
      events: Stream<AiChatStreamEvent>.value(
        const AiChatStreamEvent.textDelta('ok'),
      ),
      result: Future<AiChatStreamResult>.value(
        const AiChatStreamResult(
          reply: 'ok',
          reasoning: '',
          toolCalls: <AiToolCall>[],
        ),
      ),
    );
  }

  @override
  Future<String> testModel(AiModelConfig model) async => 'ok';

  @override
  void dispose() {
    disposed = true;
  }
}
