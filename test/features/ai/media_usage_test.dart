import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/ai_usage_store.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_token_usage.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/session_io/ai_token_usage_parser.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';
import 'package:openhand/shared/db/database_service.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-token-usage-test-',
    );
    await DatabaseService.initialize(
      databasePath: '${temporaryDirectory.path}/openhand.db',
      useNoIsolateFactory: true,
    );
  });

  tearDownAll(() async {
    await DatabaseService.instance.close();
    await temporaryDirectory.delete(recursive: true);
  });

  group('AI Token 统计', () {
    test('字符估算统一向上取整', () {
      expect(
        estimateAiTokenUsage(
          inputCharacters: 9,
          outputCharacters: 5,
          charactersPerToken: 4,
        ).toJson(),
        containsPair('total_tokens', 5),
      );
    });

    test('缓存命中率按协议口径计算', () {
      expect(
        computeCacheHitRatio(
          promptTokens: 100,
          cacheReadTokens: 80,
          cacheWriteTokens: 10,
          claudeStyle: false,
        ),
        0.8,
      );
      expect(
        computeCacheHitRatio(
          promptTokens: 10,
          cacheReadTokens: 80,
          cacheWriteTokens: 10,
          claudeStyle: true,
        ),
        0.8,
      );
    });

    test('Token 合并会补全缺失总量', () {
      const partial = AiTokenUsage(promptTokens: 20, completionTokens: 5);
      const complete = AiTokenUsage(
        promptTokens: 10,
        completionTokens: 2,
        totalTokens: 12,
      );

      expect(partial.resolvedTotalTokens, 25);
      expect(partial.merge(complete).totalTokens, 37);
    });

    test('Token 解析忽略负数并补全 Gemini 总量', () {
      final openAi = AiTokenUsageParser.parseOpenAi(<String, Object?>{
        'prompt_tokens': -10,
        'completion_tokens': 5,
        'total_tokens': -5,
      });
      final gemini = AiTokenUsageParser.parseGemini(<String, Object?>{
        'promptTokenCount': 12,
        'candidatesTokenCount': 3,
      });

      expect(openAi?.promptTokens, isNull);
      expect(openAi?.totalTokens, 5);
      expect(gemini?.totalTokens, 15);
    });

    test('使用统计持久化跨协议缓存输入口径', () async {
      const store = AiUsageStore();
      await store.clear();
      final startedAt = DateTime.utc(2026, 7, 22, 8);
      await store.insert(
        _usageRecord(
          id: 'openai-usage',
          startedAt: startedAt,
          protocol: 'openai',
          usage: const AiTokenUsage(
            promptTokens: 100,
            completionTokens: 20,
            cacheReadTokens: 80,
            cacheCreationTokens: 10,
          ),
          cacheInputTokens: 100,
        ),
      );
      await store.insert(
        _usageRecord(
          id: 'claude-usage',
          startedAt: startedAt.add(const Duration(seconds: 1)),
          protocol: 'claude',
          usage: const AiTokenUsage(
            promptTokens: 10,
            completionTokens: 5,
            totalTokens: 15,
            cacheReadTokens: 80,
            cacheCreationTokens: 10,
          ),
          cacheInputTokens: 100,
        ),
      );

      final summary = await store.loadSessionSummary(
        sessionId: 'test-session',
        source: 'thread',
      );
      expect(summary.requestCount, 2);
      expect(summary.totalTokens, 135);
      expect(summary.cacheInputTokens, 200);
      expect(summary.cacheHitRate, 0.8);
    });

    test('解析异步响应中的嵌套 usage', () {
      final usage = AiTokenUsageParser.parseResponsePayload(<String, Object?>{
        'result': <String, Object?>{
          'usage': <String, Object?>{
            'input_tokens': 120,
            'output_tokens': 30,
            'input_tokens_details': <String, Object?>{
              'cached_tokens': 80,
              'image_tokens': 40,
            },
          },
        },
      });

      expect(usage?.promptTokens, 120);
      expect(usage?.completionTokens, 30);
      expect(usage?.totalTokens, 150);
      expect(usage?.cacheReadTokens, 80);
      expect(usage?.imageInputTokens, 40);
    });

    test('媒体请求只保留最新用户提示词和参考图', () {
      final turn = mediaGenerationInputTurn(<AiChatTurn>[
        const AiChatTurn(role: AiChatRole.system, content: '系统提示'),
        const AiChatTurn(role: AiChatRole.user, content: '旧消息'),
        const AiChatTurn(
          role: AiChatRole.user,
          content: '# [6] Your latest message\n\n生成一段视频',
          parts: <AiChatContentPart>[
            AiChatContentPart.text('冗余文本片段'),
            AiChatContentPart.imageFile(
              filePath: '/tmp/reference.png',
              mimeType: 'image/png',
            ),
          ],
        ),
      ]);

      expect(turn?.content, '生成一段视频');
      expect(turn?.parts, hasLength(1));
      expect(turn?.parts.single.kind, AiChatContentPartKind.imageFile);
    });

    test('仅专用媒体端点启用请求裁剪', () {
      const request = AiCreationRequest(mode: AiCreationMode.image);
      const openAiModel = AiModelConfig(
        id: 'openai',
        baseUrl: 'https://example.com',
        authScheme: AiAuthScheme.bearer,
        token: '',
        modelId: 'custom-image-model',
        protocolType: AiProtocolType.openai,
      );
      const geminiModel = AiModelConfig(
        id: 'gemini',
        baseUrl: 'https://example.com',
        authScheme: AiAuthScheme.apiKey,
        token: '',
        modelId: 'gemini-image-model',
        protocolType: AiProtocolType.gemini,
      );

      expect(
        usesDedicatedMediaGenerationEndpoint(openAiModel, request),
        isTrue,
      );
      expect(
        usesDedicatedMediaGenerationEndpoint(geminiModel, request),
        isFalse,
      );
    });

    test('缓存趋势忽略无缓存遥测的估算轮次', () {
      final now = DateTime.utc(2026);
      final messages = <AiSessionMessage>[
        AiSessionMessage.user(id: 'user-1', content: '第一轮', createdAt: now),
        AiSessionMessage.assistant(
          id: 'assistant-1',
          content: '回复',
          createdAt: now,
          usage: const AiTokenUsage(
            promptTokens: 100,
            completionTokens: 10,
            totalTokens: 110,
            cacheReadTokens: 60,
          ),
        ),
        AiSessionMessage.user(id: 'user-2', content: '第二轮', createdAt: now),
        AiSessionMessage.assistant(
          id: 'assistant-2',
          content: '媒体地址',
          createdAt: now,
          usage: const AiTokenUsage(
            promptTokens: 20,
            completionTokens: 0,
            totalTokens: 20,
          ),
          metadata: const <String, Object?>{
            aiSessionMessageUsageEstimatedMetadataKey: true,
          },
        ),
      ];
      final session = AiSession(
        id: 'session',
        title: '测试',
        templateId: 'default',
        templateName: '默认助手',
        templateIconName: '',
        templateInternalVersion: '1',
        createdAt: now,
        updatedAt: now,
        messages: messages,
        environment: AiSessionEnvironment.fromJson(const <String, Object?>{}),
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
      );

      final trend = SessionCacheHitTrend.fromSession(
        session,
        claudeStyle: false,
      );

      expect(trend.points, hasLength(1));
      expect(trend.points.single.starterMessageId, 'user-1');
    });
  });
}

AiUsageStorageRecord _usageRecord({
  required String id,
  required DateTime startedAt,
  required String protocol,
  required AiTokenUsage usage,
  required int cacheInputTokens,
}) {
  return AiUsageStorageRecord(
    id: id,
    traceId: 'trace-$id',
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(milliseconds: 100)),
    localDate: '2026-07-22',
    localHour: '2026-07-22T08',
    durationMs: 100,
    status: 'success',
    surface: 'app',
    source: 'thread',
    operation: 'chat',
    sessionId: 'test-session',
    providerConfigId: protocol,
    providerName: protocol,
    protocol: protocol,
    modelId: 'test-model',
    apiFamily: 'chat',
    usage: usage,
    cacheInputTokens: cacheInputTokens,
    usageEstimated: false,
  );
}
