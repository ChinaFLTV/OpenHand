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

  testWidgets('[3d] Dynamic Session State is placed after user message',
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
        messages.lastIndexWhere((m) => m.role == AiChatRole.user);
    final dynamicStateIndex =
        messages.indexWhere((m) => m.content.contains('[3d] Dynamic Session State'));

    if (userTurnIndex >= 0) {
      expect(
        userTurnIndex,
        lessThan(dynamicStateIndex),
        reason: '[3d] Dynamic Session State 必须在用户消息之后。'
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
        messages.lastIndexWhere((m) => m.role == AiChatRole.user);

    if (userTurnIndex >= 0) {
      // 用户消息之后的所有 system turn 都是 volatile，包含了 [3d] Dynamic Session State
      final afterUser = messages.sublist(userTurnIndex + 1);
      final hasDynamicState = afterUser.any(
        (m) => m.role == AiChatRole.system && m.content.contains('[3d] Dynamic Session State'),
      );
      expect(hasDynamicState, isTrue,
          reason: '[3d] Dynamic Session State 必须在用户消息之后');

      // 验证用户消息之前没有 volatile 标记（[3d]、[5.5]）
      final beforeUser = messages.sublist(0, userTurnIndex);
      final volatileInStableZone = beforeUser.where(
        (m) => m.role == AiChatRole.system &&
            (m.content.contains('[3d] Dynamic Session State') ||
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
          messages.lastIndexWhere((m) => m.role == AiChatRole.user);
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

    // 验证 [3s] Static Session State 在稳定前缀中（用户消息之前）
    final prefix1HasStaticState = prefix1.any(
      (m) => m.content.contains('[3s] Static Session State'),
    );
    expect(prefix1HasStaticState, isTrue,
        reason: '[3s] Static Session State 必须在稳定前缀中（history 之前）');

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
        messages.lastIndexWhere((m) => m.role == AiChatRole.user);

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

  testWidgets('history turns are before user message, after restored contexts',
      (tester) async {
    // 验证：history 在 restored contexts 之后、用户消息之前。
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
    final userMsgIndex =
        messages.lastIndexWhere((m) => m.role == AiChatRole.user);
    final dynamicStateIndex =
        messages.indexWhere((m) => m.content.contains('[3d] Dynamic Session State'));

    // 找到历史轮次
    final firstHistoryIndex = messages.indexWhere((m) =>
        (m.role == AiChatRole.user && !m.content.contains('[6]')) ||
        m.role == AiChatRole.assistant);

    if (firstHistoryIndex >= 0 && userMsgIndex >= 0) {
      expect(firstHistoryIndex, lessThan(userMsgIndex),
          reason: 'History turns 必须在用户最新消息之前，'
              '确保模型先读取对话上下文再理解当前问题。');
      expect(userMsgIndex, lessThan(dynamicStateIndex),
          reason: '[3d] Dynamic Session State 必须在用户消息之后（volatile tail）。');
    }
  });

  testWidgets('[3s] Static Session State is immutable across turns', (tester) async {
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();

    // Round 1
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

    // Round 2: session title changed (simulating auto-title)
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
    ]).copyWith(title: 'Changed Title');

    final result2 = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session2,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session2.messages,
      latestUserMessageId: 'msg-3',
    );

    // Extract [3s] content from both rounds
    String? extract3s(List<AiChatTurn> messages) {
      for (final m in messages) {
        if (m.content.contains('[3s] Static Session State')) {
          return m.content;
        }
      }
      return null;
    }

    final s3s1 = extract3s(result1.messages);
    final s3s2 = extract3s(result2.messages);

    expect(s3s1, isNotNull, reason: 'Round 1 应有 [3s]');
    expect(s3s2, isNotNull, reason: 'Round 2 应有 [3s]');
    expect(s3s1, equals(s3s2),
        reason: '[3s] Static Session State 在标题变更后必须完全一致，'
            '否则整个合并 system message 的缓存都会断裂。');
  });

  testWidgets('[3s] Static stays byte-identical across session.mode toggle', (tester) async {
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();
    final baseMessages = [
      AiSessionMessage.user(
        id: 'msg-1',
        content: 'Hello',
        createdAt: DateTime.now().toUtc(),
      ),
    ];

    final sessionChat = _buildMinimalSession(messages: baseMessages)
        .copyWith(mode: AiSessionMode.chat);
    final sessionPlan = _buildMinimalSession(messages: baseMessages)
        .copyWith(mode: AiSessionMode.plan);

    final resultChat = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: sessionChat,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: sessionChat.messages,
      latestUserMessageId: 'msg-1',
    );
    final resultPlan = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: sessionPlan,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: sessionPlan.messages,
      latestUserMessageId: 'msg-1',
    );

    String? extract3s(List<AiChatTurn> messages) {
      for (final m in messages) {
        if (m.content.contains('[3s] Static Session State')) {
          return m.content;
        }
      }
      return null;
    }

    expect(extract3s(resultChat.messages), equals(extract3s(resultPlan.messages)),
        reason:
            'session.mode 必须留在 [3d] Dynamic；放在 [3s] 会让 plan/chat 切换断掉所有 prefix cache。');
  });

  testWidgets('[3d] Dynamic Session State contains mutable fields', (tester) async {
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
    final dynamicMsg = messages.firstWhere(
      (m) => m.content.contains('[3d] Dynamic Session State'),
    );

    // [3d] 应包含可变字段
    expect(dynamicMsg.content.contains('"title"'), isTrue,
        reason: '[3d] 必须包含 session.title（自动标题会变）');
    expect(dynamicMsg.content.contains('"date"'), isTrue,
        reason: '[3d] 必须包含 context.date（跨天会变）');
  });

  testWidgets(
      'tool-continuation turn keeps latestUser in natural position (prefix '
      'cache hit)', (tester) async {
    // 模拟一轮工具调用后的两次连续 API 调用：
    // - 第一次：latestUser=msg-1，紧跟 assistant 工具调用 + tool 结果
    // - 第二次（同一轮的“续写”）：latestUser 仍是 msg-1，但中间又多了一个
    //   assistant + tool 结果
    // 之前的实现会把 latestUser 抽出后追加到末尾，导致两次请求的 wire 顺序
    // 在 msg-1 处发散：前一次 [user, asst-toolcall, tool, user] 而后一次
    // [user, asst-toolcall, tool, asst-toolcall, tool, user]——这跟自然顺序
    // 完全不同，prefix cache 全无。修复后，latestUser 应留在自然位置，
    // 二次调用的 wire 序与首次保持 prefix 一致。
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();
    final now = DateTime.now().toUtc();

    final session1 = _buildMinimalSession(messages: [
      AiSessionMessage.user(id: 'msg-1', content: 'Search XYZ', createdAt: now),
      AiSessionMessage.toolCall(
        id: 'msg-2',
        content: '',
        createdAt: now,
        metadata: const <String, Object?>{
          'tool_calls': [
            {
              'id': 'tc-1',
              'name': 'WebSearch',
              'arguments': '{"q":"XYZ"}',
            },
          ],
        },
      ),
      AiSessionMessage.toolResult(
        id: 'msg-3',
        content: '{"hits":[1,2,3]}',
        createdAt: now,
        metadata: const <String, Object?>{
          'tool_call_id': 'tc-1',
          'tool_name': 'WebSearch',
        },
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

    final session2 = _buildMinimalSession(messages: [
      AiSessionMessage.user(id: 'msg-1', content: 'Search XYZ', createdAt: now),
      AiSessionMessage.toolCall(
        id: 'msg-2',
        content: '',
        createdAt: now,
        metadata: const <String, Object?>{
          'tool_calls': [
            {
              'id': 'tc-1',
              'name': 'WebSearch',
              'arguments': '{"q":"XYZ"}',
            },
          ],
        },
      ),
      AiSessionMessage.toolResult(
        id: 'msg-3',
        content: '{"hits":[1,2,3]}',
        createdAt: now,
        metadata: const <String, Object?>{
          'tool_call_id': 'tc-1',
          'tool_name': 'WebSearch',
        },
      ),
      AiSessionMessage.toolCall(
        id: 'msg-4',
        content: '',
        createdAt: now,
        metadata: const <String, Object?>{
          'tool_calls': [
            {
              'id': 'tc-2',
              'name': 'WebSearch',
              'arguments': '{"q":"XYZ extras"}',
            },
          ],
        },
      ),
      AiSessionMessage.toolResult(
        id: 'msg-5',
        content: '{"hits":[4,5]}',
        createdAt: now,
        metadata: const <String, Object?>{
          'tool_call_id': 'tc-2',
          'tool_name': 'WebSearch',
        },
      ),
    ]);
    final result2 = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session2,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session2.messages,
      latestUserMessageId: 'msg-1',
    );

    // 提取“稳定区” = 用户消息及之前的所有 turn（不含末尾 volatile system 块）。
    // 修复后，第一次和第二次的稳定区 wire 序列在 user 消息之前/之中应严格
    // 互为前缀关系：second 的前 N 项 == first 的前 N 项（N = first.length 中
    // 直到 user 那条 turn 的位置）。
    List<AiChatTurn> stableHeadIncludingUser(List<AiChatTurn> messages) {
      final firstUser = messages.indexWhere((m) => m.role == AiChatRole.user);
      if (firstUser < 0) return messages;
      return messages.sublist(0, firstUser + 1);
    }

    final head1 = stableHeadIncludingUser(result1.messages);
    final head2 = stableHeadIncludingUser(result2.messages);

    // 关键断言：head1 应当是 head2 的严格前缀 —— 即 result2 的前 head1.length
    // 项与 head1 完全一致（role + content）。否则 latestUser 的位置就跑了，
    // prefix cache 必然失效。
    expect(result2.messages.length >= head1.length, isTrue);
    for (var i = 0; i < head1.length; i++) {
      expect(result2.messages[i].role, head1[i].role,
          reason: '工具续写时 latestUser 之前/之中 wire 顺序必须保持稳定 '
              '(turn $i role 不一致)');
      expect(result2.messages[i].content, head1[i].content,
          reason: '工具续写时 latestUser 之前/之中 wire 内容必须保持稳定 '
              '(turn $i content 不一致)');
    }
    // sanity: head2 在自然位置（即第一次出现 user）应当与 head1 末尾的 user 对齐
    expect(head2.last.role, AiChatRole.user);
  });
}
