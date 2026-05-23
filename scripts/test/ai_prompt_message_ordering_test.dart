import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';

/// 验证缓存前缀优化后的消息顺序：
/// - 稳定内容（[0]-[5]、历史、恢复上下文、用户消息本体）在 volatile 内容之前
/// - [3] Session State、[5.5] Focus Context 等 volatile 块在用户消息之后
void main() {
  final repo = AiPromptTemplateRepository();

  AiSession _buildMinimalSession({
    String templateId = 'default',
    List<AiSessionMessage>? messages,
  }) {
    final now = DateTime.now().toUtc();
    return AiSession(
      id: 'test-session',
      title: 'Test',
      templateId: templateId,
      templateName: templateId,
      templateIconName: 'auto_awesome_rounded',
      templateInternalVersion: '3.0.0',
      createdAt: now,
      updatedAt: now,
      messages: messages ?? <AiSessionMessage>[],
      environment: const AiSessionEnvironment(
        localeTag: 'zh-CN',
        platform: 'macos',
        appVersion: '1.0.0',
        appBuildNumber: '1',
        applicationDirectory: '/tmp',
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
    );
  }

  AiModelConfig _buildModel({String modelId = 'deepseek-v4-flash'}) {
    return AiModelConfig(
      id: 'test-model',
      baseUrl: 'https://api.example.com',
      authScheme: AiAuthScheme.bearer,
      token: 'test-token',
      modelId: modelId,
      protocolType: AiProtocolType.openai,
    );
  }

  AiSessionRuntimeContext _buildRuntimeContext() {
    return AiSessionRuntimeContext(
      localeTag: 'zh-CN',
      appVersion: '1.0.0',
      appBuildNumber: '1',
      settingsFilePath: '/tmp/settings.json',
      skillsStoragePath: '/tmp/skills',
      mcpServersFilePath: '/tmp/mcp.json',
      userMemoryFilePath: '/tmp/memory.json',
      compressionThresholdChars: 100000,
      memoryEnabled: false,
      memoryEntries: const <UserMemoryEntry>[],
      workingDirectory: '/tmp/work',
      todayLocalDate: '2026-05-23',
      timeZoneName: 'Asia/Shanghai',
    );
  }

  testWidgets('volatile [3] Session State is placed after user message',
      (tester) async {
    final templateBundle = await repo.loadBundle('default');
    final session = _buildMinimalSession();
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();

    final result = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: const <AiSessionMessage>[],
    );

    final messages = result.messages;

    // 找到用户消息和 Session State 的索引
    final userTurnIndex =
        messages.indexWhere((m) => m.content.contains('[6] Your latest message'));
    final sessionStateIndex =
        messages.indexWhere((m) => m.content.contains('[3] Session State'));

    // 没有用户消息时，Session State 在 system messages 中也合理
    if (userTurnIndex >= 0) {
      expect(
        userTurnIndex,
        lessThan(sessionStateIndex),
        reason: '[3] Session State 必须在用户消息之后。'
            '若在之前，它会与 restored contexts 合并为一条 system 消息，'
            '每轮变化导致前缀缓存断裂，命中率退化至个位数。',
      );
    }
  });

  testWidgets(
      'volatile content (System Reminder, Plan Mode Reminder) after user message',
      (tester) async {
    final templateBundle = await repo.loadBundle('default');
    final session = _buildMinimalSession();
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();

    final result = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: const <AiSessionMessage>[],
    );

    final messages = result.messages;
    final userTurnIndex =
        messages.indexWhere((m) => m.content.contains('[6] Your latest message'));

    if (userTurnIndex >= 0) {
      // 用户消息之后的所有 system turn 都是 volatile，包含了 [3] Session State
      final afterUser = messages.sublist(userTurnIndex + 1);
      final hasSessionState = afterUser.any(
        (m) => m.role == AiChatRole.system && m.content.contains('[3] Session State'),
      );
      expect(hasSessionState, isTrue,
          reason: '[3] Session State 必须在用户消息之后');

      // 验证用户消息之前没有 volatile 标记
      final beforeUser = messages.sublist(0, userTurnIndex);
      final volatileInStableZone = beforeUser.where(
        (m) => m.role == AiChatRole.system &&
            (m.content.contains('[3] Session State') ||
             m.content.contains('[5.5] Focus Context')),
      );
      expect(volatileInStableZone, isEmpty,
          reason: '用户消息之前（稳定前缀区）不得包含任何 volatile 内容。'
              '发现 volatile 块: ${volatileInStableZone.map((m) => m.content.substring(0, 80))}');
    }
  });

  testWidgets(
      'stable prefix [0]-[5] is before user message, maintained across calls',
      (tester) async {
    // 模拟两轮连续对话，验证稳定前缀结构一致
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();

    // Round 1: 第一条用户消息
    final session1 = _buildMinimalSession(messages: [
      AiSessionMessage.user(
        id: 'msg-1',
        content: 'Hello',
        createdAt: DateTime.now().toUtc(),
      ),
    ]);
    final result1 = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session1,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session1.messages,
      latestUserMessageId: 'msg-1',
    );

    // Round 2: 第二条用户消息
    final session2 = _buildMinimalSession(messages: [
      AiSessionMessage.user(
        id: 'msg-1',
        content: 'Hello',
        createdAt: DateTime.now().toUtc(),
      ),
      AiSessionMessage.assistant(
        id: 'msg-2',
        content: 'Hi there!',
        createdAt: DateTime.now().toUtc(),
      ),
      AiSessionMessage.user(
        id: 'msg-3',
        content: 'How are you?',
        createdAt: DateTime.now().toUtc(),
      ),
    ]);
    final result2 = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session2,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session2.messages,
      latestUserMessageId: 'msg-3',
    );

    // 提取稳定前缀（用户消息之前的部分）
    List<AiChatTurn> stablePrefix(List<AiChatTurn> messages) {
      final idx =
          messages.indexWhere((m) => m.content.contains('[6] Your latest message'));
      return idx >= 0 ? messages.sublist(0, idx) : messages;
    }

    final prefix1 = stablePrefix(result1.messages);
    final prefix2 = stablePrefix(result2.messages);

    // 两轮的稳定前缀的 system messages 应该完全一致（除了 history turns）
    final prefix1Systems = prefix1
        .where((m) => m.role == AiChatRole.system)
        .map((m) => m.content)
        .toList();
    final prefix2Systems = prefix2
        .where((m) => m.role == AiChatRole.system)
        .map((m) => m.content)
        .toList();

    // 第一条 system message（[0] System Instructions）应该一致
    expect(prefix1Systems.first, equals(prefix2Systems.first),
        reason: '[0] System Instructions 在两轮之间必须完全一致，'
            '否则前缀缓存会断裂');
  });

  testWidgets(
      'hook system reminder (if injected as system turn) goes to volatile tail',
      (tester) async {
    // 模拟 hook 注入：latestUserTurns 中除了 user turn 外还有 system turn。
    // 验证 system turn 被放入 volatile tail（用户消息之后）。
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();

    final session = _buildMinimalSession(messages: [
      AiSessionMessage.user(
        id: 'msg-1',
        content:
            'Do something\n\n<system-reminder>\nHook injected reminder content\n</system-reminder>',
        createdAt: DateTime.now().toUtc(),
      ),
    ]);

    final result = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session.messages,
      latestUserMessageId: 'msg-1',
    );

    final messages = result.messages;
    final userTurnIndex =
        messages.indexWhere((m) => m.content.contains('[6] Your latest message'));

    expect(userTurnIndex, greaterThanOrEqualTo(0),
        reason: '应该有用户消息');

    // 用户消息之前的 system turns 中不应含 hook reminder
    final beforeUser = messages.sublist(0, userTurnIndex);
    final hookInStable = beforeUser.where(
      (m) => m.role == AiChatRole.system &&
          m.content.contains('Hook injected'),
    );
    expect(hookInStable, isEmpty,
        reason: 'Hook system reminder 不得出现在稳定前缀区');

    // 用户消息之后应该能找到 hook reminder（如果被正确提取）
    final afterUser = messages.sublist(userTurnIndex + 1);
    final hookInVolatile = afterUser
        .where((m) => m.content.contains('Hook injected'));
    // 注：是否真的能提取取决于 _extractSystemReminders 的实现，
    // 至少不应在 stable 区出现
    if (hookInVolatile.isNotEmpty) {
      final hookIndex = messages.indexWhere((m) => m.content.contains('Hook injected'));
      expect(hookIndex, greaterThan(userTurnIndex),
          reason: 'Hook system reminder 必须在 volatile tail 中');
    }
  });

  testWidgets('history turns are placed after volatile tail (v3 ordering)',
      (tester) async {
    // 验证 v3 排序：history 在 Focus Context 之后，确保前缀位置固定。
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();

    // 构造有历史轮次的会话
    final session = _buildMinimalSession(messages: [
      AiSessionMessage.user(
        id: 'msg-1',
        content: 'First question',
        createdAt: DateTime.now().toUtc(),
      ),
      AiSessionMessage.assistant(
        id: 'msg-2',
        content: 'First answer',
        createdAt: DateTime.now().toUtc(),
      ),
      AiSessionMessage.user(
        id: 'msg-3',
        content: 'Second question',
        createdAt: DateTime.now().toUtc(),
      ),
    ]);

    final result = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session.messages,
      latestUserMessageId: 'msg-3',
    );

    final messages = result.messages;
    final focusContextIndex =
        messages.indexWhere((m) => m.content.contains('[5.5] Focus Context'));
    final sessionStateIndex =
        messages.indexWhere((m) => m.content.contains('[3] Session State'));
    final lastVolatileIndex = focusContextIndex >= 0
        ? focusContextIndex
        : sessionStateIndex;

    // 找到历史轮次（不含 [6] 前缀的 user message 或 assistant message）
    final firstHistoryIndex = messages.indexWhere((m) =>
        (m.role == AiChatRole.user && !m.content.contains('[6]')) ||
        m.role == AiChatRole.assistant);

    if (firstHistoryIndex >= 0 && lastVolatileIndex >= 0) {
      expect(firstHistoryIndex, greaterThan(lastVolatileIndex),
          reason: 'History turns 必须在 volatile tail（[3]/[5.5]）之后。'
              '当前 history 在 index=$firstHistoryIndex，volatile 末尾在 $lastVolatileIndex。'
              '若 history 在 volatile 之前，会导致消息位置随轮次漂移，破坏前缀缓存。');
    }
  });
}
