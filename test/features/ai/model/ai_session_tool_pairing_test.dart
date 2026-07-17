import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  final createdAt = DateTime.utc(2026, 7, 17);
  late Directory temporaryDirectory;
  late AiSessionStore store;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-tool-pairing-',
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

  AiSessionMessage toolCall(String callId) {
    return AiSessionMessage.toolCall(
      id: 'call-$callId',
      content: 'ToolSearch',
      createdAt: createdAt,
      metadata: <String, Object?>{
        'tool_call_id': callId,
        'tool_name': 'ToolSearch',
      },
    );
  }

  AiSessionMessage toolResult(String callId) {
    return AiSessionMessage.toolResult(
      id: 'result-$callId',
      content: '{"status":"success"}',
      createdAt: createdAt,
      metadata: <String, Object?>{
        'tool_call_id': callId,
        'tool_name': 'ToolSearch',
      },
    );
  }

  AiSessionMessage assistant(String id) {
    return AiSessionMessage.assistant(
      id: id,
      content: id,
      createdAt: createdAt,
    );
  }

  AiSession session(
    List<AiSessionMessage> messages, {
    required AiSessionMessageLoadState loadState,
    String id = 'session',
  }) {
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
      messageLoadState: loadState,
      messageWindowStartIndex: loadState == AiSessionMessageLoadState.windowed
          ? 8
          : 0,
      messageTotalCount:
          messages.length +
          (loadState == AiSessionMessageLoadState.windowed ? 8 : 0),
    );
  }

  test('能够识别分页窗口中缺失的工具调用', () {
    expect(
      unmatchedTranscriptToolCallIds(<AiSessionMessage>[toolResult('one')]),
      <String>{'one'},
    );
    expect(
      unmatchedTranscriptToolCallIds(<AiSessionMessage>[
        toolCall('one'),
        toolResult('one'),
      ]),
      isEmpty,
    );
  });

  test('部分历史不会把未配对结果渲染成通用工具卡片', () {
    final value = session(<AiSessionMessage>[
      toolResult('one'),
    ], loadState: AiSessionMessageLoadState.windowed);

    expect(value.displayMessages, isEmpty);
  });

  test('部分历史中已配对的工具调用保持完整卡片', () {
    final call = toolCall('one');
    final value = session(<AiSessionMessage>[
      call,
      toolResult('one'),
    ], loadState: AiSessionMessageLoadState.windowed);

    expect(value.displayMessages, <AiSessionMessage>[call]);
  });

  test('完整历史仍保留真实孤立工具结果', () {
    final result = toolResult('one');
    final value = session(<AiSessionMessage>[
      result,
    ], loadState: AiSessionMessageLoadState.complete);

    expect(value.displayMessages, <AiSessionMessage>[result]);
  });

  test('消息分页会自动补齐跨边界的工具调用', () async {
    final messages = <AiSessionMessage>[
      assistant('before'),
      toolCall('one'),
      toolCall('two'),
      toolResult('one'),
      toolResult('two'),
      assistant('after'),
    ];
    await store.save(
      session(messages, loadState: AiSessionMessageLoadState.complete),
    );

    final page = await store.loadMessages('session', limit: 3, offset: 3);

    expect(page.offset, 0);
    expect(page.messages.map((message) => message.id), <String>[
      'before',
      'call-one',
      'call-two',
      'result-one',
      'result-two',
      'after',
    ]);
    expect(unmatchedTranscriptToolCallIds(page.messages), isEmpty);
  });

  test('首屏尾窗从工具结果开始时仍保持完整分组', () async {
    final loaded = await store.loadSessionTailWindow(
      'session',
      limit: 3,
      characterBudget: 100000,
    );

    expect(loaded, isNotNull);
    expect(loaded!.messageWindowStartIndex, 0);
    expect(unmatchedTranscriptToolCallIds(loaded.messages), isEmpty);
    expect(loaded.displayMessages.map((message) => message.id), <String>[
      'before',
      'call-one',
      'call-two',
      'after',
    ]);
  });

  test('首屏消息延迟审计重字段并保留渲染元数据', () async {
    final metadata = <String, Object?>{
      'request_payload': <String, Object?>{
        'messages': List<String>.filled(128, '大段请求内容'),
      },
      'response_raw': List<String>.filled(128, '大段响应内容').join(),
      'composed_prompt_turns': List<String>.filled(64, '提示词轮次'),
      'composed_prompt_text': List<String>.filled(64, '完整提示词').join(),
      'prompt_metadata': <String, Object?>{'cache_enabled': true},
      aiSessionMessageContentFormatKey: 'html',
      'tool_name': 'MachineTerminalExec',
    };
    await store.save(
      session(
        <AiSessionMessage>[
          AiSessionMessage.assistant(
            id: 'heavy-message',
            content: '<p>结果</p>',
            createdAt: createdAt,
            metadata: metadata,
          ),
        ],
        loadState: AiSessionMessageLoadState.complete,
        id: 'heavy-session',
      ),
    );

    final loaded = await store.loadSessionTailWindow(
      'heavy-session',
      limit: 8,
      characterBudget: 14000,
    );
    final page = await store.loadMessages(
      'heavy-session',
      deferTelemetryMetadata: true,
    );
    final full = await store.loadMessage('heavy-session', 'heavy-message');

    for (final compact in <AiSessionMessage>[
      loaded!.messages.single,
      page.messages.single,
    ]) {
      expect(
        aiSessionMessageHasDeferredTelemetryMetadata(compact.metadata),
        isTrue,
      );
      expect(compact.metadata, isNot(contains('request_payload')));
      expect(compact.metadata, isNot(contains('response_raw')));
      expect(compact.metadata[aiSessionMessageContentFormatKey], 'html');
      expect(compact.metadata['tool_name'], 'MachineTerminalExec');
    }
    expect(full!.metadata['request_payload'], isNotNull);
    expect(full.metadata['response_raw'], isNotNull);
    expect(
      aiSessionMessageHasDeferredTelemetryMetadata(full.metadata),
      isFalse,
    );
  });

  test('首屏知识库继承只读取最近会话边界', () async {
    final knowledgeMetadata = <String, Object?>{
      'knowledge_base': <String, Object?>{
        'enabled': true,
        'status': 'success',
        'results': <Object?>[
          <String, Object?>{'chunk_id': 'chunk-1', 'content': '知识内容'},
        ],
      },
      'request_payload': List<String>.filled(128, '大段请求内容').join(),
    };
    await store.save(
      session(
        <AiSessionMessage>[
          AiSessionMessage.user(
            id: 'knowledge-user',
            content: '查询知识',
            createdAt: createdAt,
            metadata: knowledgeMetadata,
          ),
          AiSessionMessage.reasoning(
            id: 'knowledge-reasoning',
            content: '分析中',
            createdAt: createdAt,
          ),
          AiSessionMessage.assistant(
            id: 'knowledge-answer',
            content: '知识回答',
            createdAt: createdAt,
          ),
        ],
        loadState: AiSessionMessageLoadState.complete,
        id: 'knowledge-session',
      ),
    );

    final loaded = await store.loadSessionTailWindow(
      'knowledge-session',
      limit: 2,
      characterBudget: 14000,
    );
    final answer = loaded!.messages.singleWhere(
      (message) => message.id == 'knowledge-answer',
    );

    expect(answer.metadata['knowledge_base'], isNotNull);
  });
}
