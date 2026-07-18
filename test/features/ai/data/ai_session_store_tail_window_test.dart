import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  final createdAt = DateTime.utc(2026, 7, 18);
  late Directory temporaryDirectory;
  late AiSessionStore store;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-tail-window-',
    );
    await DatabaseService.initialize(
      databasePath: p.join(temporaryDirectory.path, 'openhand.db'),
      useNoIsolateFactory: true,
    );
    store = AiSessionStore(
      sessionsDirectoryPath: p.join(temporaryDirectory.path, 'sessions'),
    );
  });

  tearDownAll(() async {
    await DatabaseService.instance.close();
    await temporaryDirectory.delete(recursive: true);
  });

  AiSession session(String id, List<AiSessionMessage> messages) {
    return AiSession(
      id: id,
      title: '测试会话',
      templateId: 'default',
      templateName: '默认助手',
      templateIconName: '',
      templateInternalVersion: '1',
      createdAt: createdAt,
      updatedAt: createdAt,
      messages: messages,
      environment: AiSessionEnvironment.fromJson(const <String, Object?>{}),
      statistics: const AiSessionStatistics.initial(),
      recentErrors: const <AiSessionErrorRecord>[],
      messageLoadState: AiSessionMessageLoadState.complete,
      messageTotalCount: messages.length,
    );
  }

  test('首屏将超大最新消息限制为有界预览且可按需读取完整内容', () async {
    final content = List<String>.filled(50000, '长内容').join();
    const sessionId = 'large-tail-session';
    const messageId = 'large-tail-message';
    await store.save(
      session(sessionId, <AiSessionMessage>[
        AiSessionMessage.assistant(
          id: messageId,
          content: content,
          createdAt: createdAt,
        ),
      ]),
    );

    final loaded = await store.loadSessionTailWindow(
      sessionId,
      limit: 8,
      characterBudget: 14000,
    );
    final preview = loaded!.messages.single;
    final full = await store.loadMessage(sessionId, messageId);

    expect(preview.content.length, 4096);
    expect(preview.content.length, lessThanOrEqualTo(14000));
    expect(preview.characterCount, content.length);
    expect(preview.metadata[aiSessionMessageContentPreviewMetadataKey], isTrue);
    expect(loaded.messageLoadState, AiSessionMessageLoadState.windowed);
    expect(loaded.hasCompleteMessages, isFalse);
    expect(full!.content, content);
    expect(full.metadata[aiSessionMessageContentPreviewMetadataKey], isNull);
  });

  test('首屏工具配对补偿仍受总字符预算约束', () async {
    const sessionId = 'bounded-tool-context-session';
    const callId = 'call-1';
    final hugeArguments = List<String>.filled(20000, '参数').join();
    await store.save(
      session(sessionId, <AiSessionMessage>[
        AiSessionMessage.toolCall(
          id: 'tool-call',
          content: hugeArguments,
          createdAt: createdAt,
          metadata: const <String, Object?>{
            'tool_call_id': callId,
            'tool_name': 'ToolSearch',
          },
        ),
        AiSessionMessage.assistant(
          id: 'middle',
          content: '中间消息',
          createdAt: createdAt,
        ),
        AiSessionMessage.toolResult(
          id: 'tool-result',
          content: '结果',
          createdAt: createdAt,
          metadata: const <String, Object?>{
            'tool_call_id': callId,
            'tool_name': 'ToolSearch',
          },
        ),
      ]),
    );

    final loaded = await store.loadSessionTailWindow(
      sessionId,
      limit: 1,
      characterBudget: 64,
    );

    expect(
      loaded!.messages.fold<int>(
        0,
        (sum, message) => sum + message.content.length,
      ),
      lessThanOrEqualTo(64),
    );
  });

  test('历史分页可继续延迟大型审计元数据', () async {
    const sessionId = 'deferred-page-session';
    const messageId = 'deferred-page-message';
    final payload = List<String>.filled(20000, '审计').join();
    await store.save(
      session(sessionId, <AiSessionMessage>[
        AiSessionMessage.assistant(
          id: messageId,
          content: '结果',
          createdAt: createdAt,
          metadata: <String, Object?>{
            'request_payload': payload,
            'response_raw': payload,
            aiSessionMessageContentFormatKey: 'html',
          },
        ),
      ]),
    );

    final page = await store.loadMessages(
      sessionId,
      deferTelemetryMetadata: true,
    );
    final compact = page.messages.single;

    expect(
      aiSessionMessageHasDeferredTelemetryMetadata(compact.metadata),
      isTrue,
    );
    expect(compact.metadata, isNot(contains('request_payload')));
    expect(compact.metadata, isNot(contains('response_raw')));
    expect(compact.metadata[aiSessionMessageContentFormatKey], 'html');
  });
}
