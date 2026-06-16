import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_attachment.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_tool_budget_strategy.dart';

void main() {
  const strategy = AiPromptToolBudgetStrategy();

  group('AiPromptToolBudgetStrategy', () {
    test(
      'uses direct-answer mode for exported short default-template turns',
      () {
        for (final content in <String>[
          '泥嚎',
          '想你了',
          '分手',
          '我已经有心上人了，不好意思。',
          '你难道就没有什么要对我说的吗？',
          'ps 和 kill 如何按照父pid去筛选呢？',
          '好的谢谢你',
          '你是谁来着',
        ]) {
          final session = _sessionWithLatestUser(content);
          final decision = strategy.decide(
            session: session,
            latestUserMessageId: 'u1',
            toolRoundCount: 0,
            creationRequestActive: false,
          );

          expect(decision.omitsRuntimeTools, isTrue, reason: content);
        }
      },
    );

    test('keeps full tools for workspace and local action intents', () {
      for (final content in <String>[
        '请你帮我运行 flutter analyze 看看这个项目',
        '帮我读取 /Users/me/project/lib/main.dart',
        '修复这个仓库里的报错',
        '最新的 Flutter 版本是多少？',
        '帮我搜一下 OpenAI 最新模型',
        '查一下今天上海天气',
        '修复 bug',
        '运行测试',
        '创建文件',
        '生成图片：一只机械猫',
        '画一张赛博城市海报',
        'continue',
      ]) {
        final session = _sessionWithLatestUser(content);
        final decision = strategy.decide(
          session: session,
          latestUserMessageId: 'u1',
          toolRoundCount: 0,
          creationRequestActive: false,
        );

        expect(decision.omitsRuntimeTools, isFalse, reason: content);
      }
    });

    test('keeps full tools for specialized templates and active plans', () {
      final programmingSession = _sessionWithLatestUser(
        'ps 和 kill 如何按照父pid去筛选呢？',
        templateId: 'programming_expert',
      );
      expect(
        strategy
            .decide(
              session: programmingSession,
              latestUserMessageId: 'u1',
              toolRoundCount: 0,
              creationRequestActive: false,
            )
            .omitsRuntimeTools,
        isFalse,
      );

      final plannedSession = _sessionWithLatestUser(
        '好的谢谢你',
        todoItems: const <AiSessionTodoItem>[
          AiSessionTodoItem(id: 't1', content: '修复缓存', status: 'pending'),
        ],
      );
      expect(
        strategy
            .decide(
              session: plannedSession,
              latestUserMessageId: 'u1',
              toolRoundCount: 0,
              creationRequestActive: false,
            )
            .omitsRuntimeTools,
        isFalse,
      );
    });

    test('keeps full tools when latest user message has attachments', () {
      final session = _sessionWithLatestUser(
        '这是什么？',
        metadata: const <String, Object?>{
          aiSessionMessageAttachmentsMetadataKey: <Object?>[
            <String, Object?>{'id': 'a1', 'storage_path': '/tmp/a.png'},
          ],
        },
      );
      final decision = strategy.decide(
        session: session,
        latestUserMessageId: 'u1',
        toolRoundCount: 0,
        creationRequestActive: false,
      );

      expect(decision.omitsRuntimeTools, isFalse);
    });
  });
}

AiSession _sessionWithLatestUser(
  String content, {
  String templateId = 'default',
  Map<String, Object?> metadata = const <String, Object?>{},
  List<AiSessionTodoItem> todoItems = const <AiSessionTodoItem>[],
}) {
  final now = DateTime.utc(2026, 6, 16);
  return AiSession(
    id: 's1',
    title: 'test',
    templateId: templateId,
    templateName: templateId,
    templateIconName: 'auto_awesome_rounded',
    templateInternalVersion: '1.0.0',
    createdAt: now,
    updatedAt: now,
    messages: <AiSessionMessage>[
      AiSessionMessage.user(
        id: 'u1',
        content: content,
        createdAt: now,
        metadata: metadata,
      ),
    ],
    environment: const AiSessionEnvironment(
      localeTag: 'zh-Hans',
      platform: 'macos',
      appVersion: '0.1.0',
      appBuildNumber: '1',
      applicationDirectory: '/tmp/openhand',
      homeDirectory: '/tmp',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.json',
      sessionsDirectoryPath: '/tmp/sessions',
      compressionThresholdChars: 100000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const <AiSessionErrorRecord>[],
    todoItems: todoItems,
  );
}
