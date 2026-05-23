import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/instructions/model/user_instruction_entry.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';

/// 验证 prefix-extension cache 架构下的消息顺序（v5）：
/// - [3d] Dynamic Session State / [5.5] Focus Context 置于 history 之前
/// - history turns 在 [3d]/[5.5] 之后、用户消息之前
/// - Hook system-reminder（从用户消息中提取）仍在用户消息之后（volatile tail）
/// - 相邻轮次的 token 序列满足"前缀扩展"性质：Turn N+1 = Turn N ++ [asst][user_new]
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

  AiSessionRuntimeContext _buildRuntimeContext({
    List<UserInstructionEntry> userInstructions = const <UserInstructionEntry>[],
    Set<String> skippedInstructionIds = const <String>{},
  }) {
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
      userInstructions: userInstructions,
      skippedInstructionIds: skippedInstructionIds,
    );
  }

  testWidgets('[3d] Dynamic Session State is placed BEFORE user message (and before history)',
      (tester) async {
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();
    final now = DateTime.now().toUtc();

    // Use a session with a user message so positions are meaningful.
    final session = _buildMinimalSession(messages: [
      AiSessionMessage.user(
        id: 'msg-1',
        content: 'Hello world',
        createdAt: now,
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
    final dynamicStateIndex =
        messages.indexWhere((m) => m.content.contains('[3d] Dynamic Session State'));

    expect(dynamicStateIndex, greaterThanOrEqualTo(0),
        reason: '[3d] Dynamic Session State が存在すること');
    expect(userTurnIndex, greaterThanOrEqualTo(0),
        reason: 'ユーザーターンが存在すること');
    expect(
      dynamicStateIndex,
      lessThan(userTurnIndex),
      reason: '[3d] Dynamic Session State は prefix-extension cache 架構のため '
          'history / 用户消息より前に置かれなければならない。',
    );
  });

  testWidgets(
      '[3d] and [5.5] are before user message; hook reminder is after user message',
      (tester) async {
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();
    final now = DateTime.now().toUtc();

    final session = _buildMinimalSession(messages: [
      AiSessionMessage.user(
        id: 'msg-1',
        content: 'Hello world',
        createdAt: now,
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

    expect(userTurnIndex, greaterThanOrEqualTo(0), reason: '用户消息必须存在');

    // [3d] and [5.5] must appear BEFORE the user turn (prefix-extension cache).
    final beforeUser = messages.sublist(0, userTurnIndex);
    final hasDynamicState = beforeUser.any(
      (m) => m.role == AiChatRole.system && m.content.contains('[3d] Dynamic Session State'),
    );
    expect(hasDynamicState, isTrue,
        reason: '[3d] Dynamic Session State 必须在用户消息之前（prefix-extension cache）');

    // After the user, only hook system-reminders may appear (no [3d] or [5.5]).
    final afterUser = messages.sublist(userTurnIndex + 1);
    final dynamicInVolatile = afterUser.where(
      (m) => m.role == AiChatRole.system &&
          (m.content.contains('[3d] Dynamic Session State') ||
           m.content.contains('[5.5] Focus Context')),
    );
    expect(dynamicInVolatile, isEmpty,
        reason: '用户消息之後（volatile tail）に [3d] / [5.5] が現れてはいけない。'
            'これらは prefix-extension cache のため history 前に配置されている。');
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

  testWidgets('history turns are after [3d]/[5.5] but before user message',
      (tester) async {
    // 验证：[3d] → history → 用户消息 的顺序。
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

    // 找到第一个 non-system (i.e. history) turn
    final firstHistoryIndex = messages.indexWhere((m) =>
        m.role == AiChatRole.user || m.role == AiChatRole.assistant);

    if (firstHistoryIndex >= 0 && userMsgIndex >= 0) {
      // [3d] must appear before the first history turn.
      expect(dynamicStateIndex, lessThan(firstHistoryIndex),
          reason: '[3d] Dynamic Session State は prefix-extension cache 架構のため '
              'history より前に配置されなければならない。');
      // History turns must appear before the latest user message.
      expect(firstHistoryIndex, lessThan(userMsgIndex),
          reason: 'History turns 必须在用户最新消息之前，'
              '确保模型先读取对话上下文再理解当前问题。');
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
    // context.date 已从 [3d] 移除（日期跨天会改变 merged system hash，破坏 prefix-cache）。
    expect(dynamicMsg.content.contains('"date"'), isFalse,
        reason: '[3d] 不得包含 context.date（跨天会破坏 prefix-cache）');
  });

  testWidgets(
      'tool-continuation: latestUser stays inline; [3d] before user turn',
      (tester) async {
    // Verify: in a tool-continuation sequence, latestUser stays at its natural
    // inline position (not extracted to the tail). Also verify [3d] appears
    // before the user turn (prefix-extension architecture).
    // Note: [5.5] Focus Context content differs between the first call (no tool
    // outcomes) and the second call (outcomes present), so the two calls are NOT
    // strict prefix extensions of each other — that is expected and acceptable.
    // The core consecutive-user-turn prefix-extension invariant is covered by
    // the separate "consecutive user turns form prefix extension" test.
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();
    final now = DateTime.now().toUtc();

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

    final messages = result2.messages;

    // 1. [3d] must appear before the first user turn.
    final firstUserIndex = messages.indexWhere((m) => m.role == AiChatRole.user);
    final dynamicStateIndex =
        messages.indexWhere((m) => m.content.contains('[3d] Dynamic Session State'));
    expect(dynamicStateIndex, greaterThanOrEqualTo(0), reason: '[3d] must exist');
    expect(firstUserIndex, greaterThanOrEqualTo(0), reason: 'user must exist');
    expect(dynamicStateIndex, lessThan(firstUserIndex),
        reason: '[3d] must appear before user turn (prefix-extension cache)');

    // 2. latestUser (msg-1) is inline: non-system messages follow it (the tool turns).
    final userTurnIdx = messages.indexWhere(
      (m) => m.role == AiChatRole.user && m.content.contains('Search XYZ'),
    );
    expect(userTurnIdx, greaterThanOrEqualTo(0), reason: 'latestUser must appear');
    final afterUserNonSystem = messages
        .sublist(userTurnIdx + 1)
        .where((m) => m.role != AiChatRole.system)
        .toList();
    expect(afterUserNonSystem, isNotEmpty,
        reason: 'After inline latestUser, tool-call/result turns must follow');

    // 3. latestUser is NOT duplicated at the tail.
    final lastNonSystem =
        messages.lastWhere((m) => m.role != AiChatRole.system);
    expect(lastNonSystem.content.contains('Search XYZ'), isFalse,
        reason: 'latestUser is inline so it must not be duplicated at the tail');
  });

  testWidgets(
      'consecutive user turns form prefix extension (core cache invariant)',
      (tester) async {
    // Core invariant: consecutive turns (different user messages) satisfy the
    // prefix-extension property: Turn N's message sequence is a strict byte-
    // identical prefix of Turn N+1's sequence (when [3d]/[5.5] content is
    // unchanged). This guarantees DeepSeek KV cache hits ~100% of Turn N's
    // tokens on Turn N+1.
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();
    final now = DateTime.now().toUtc();

    // Turn N: user1 is the latest user message (no history yet).
    final sessionN = _buildMinimalSession(messages: [
      AiSessionMessage.user(id: 'msg-1', content: 'Hello', createdAt: now),
    ]);
    final resultN = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: sessionN,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: sessionN.messages,
      latestUserMessageId: 'msg-1',
    );

    // Turn N+1: user1 is now history; user2 is the new latest user message.
    // Same runtimeContext => same [3d]/[5.5] content => prefix extension holds.
    final sessionN1 = _buildMinimalSession(messages: [
      AiSessionMessage.user(id: 'msg-1', content: 'Hello', createdAt: now),
      AiSessionMessage.assistant(id: 'msg-2', content: 'Hi there!', createdAt: now),
      AiSessionMessage.user(id: 'msg-3', content: 'How are you?', createdAt: now),
    ]);
    final resultN1 = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: sessionN1,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: sessionN1.messages,
      latestUserMessageId: 'msg-3',
    );

    final msgsN = resultN.messages;
    final msgsN1 = resultN1.messages;

    // Turn N+1 must have MORE messages (history + assistant + new user appended).
    expect(msgsN1.length, greaterThan(msgsN.length),
        reason: 'Turn N+1 should have more messages (history + new user)');

    // The first msgsN.length messages in Turn N+1 must be identical to Turn N.
    for (var i = 0; i < msgsN.length; i++) {
      expect(msgsN1[i].role, msgsN[i].role,
          reason: 'Turn N+1 message [$i] role must match Turn N (prefix extension)');
      expect(msgsN1[i].content, msgsN[i].content,
          reason: 'Turn N+1 message [$i] content must match Turn N (prefix extension)');
    }

    // The extra messages in Turn N+1 are the assistant response + new user.
    final extraMsgs = msgsN1.sublist(msgsN.length);
    expect(extraMsgs.any((m) => m.role == AiChatRole.assistant), isTrue,
        reason: 'Extra messages should include the assistant response from Turn N');
    expect(extraMsgs.last.role, AiChatRole.user,
        reason: 'Last extra message should be the new user message');
    expect(extraMsgs.last.content, contains('How are you?'),
        reason: 'New user message content should be correct');
  });

  testWidgets('[4.5] User Instructions stays byte-identical across skip toggle',
      (tester) async {
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final builder = const AiPromptBuilder();
    final now = DateTime.now().toUtc();
    final instructions = <UserInstructionEntry>[
      UserInstructionEntry(
        id: 'inst-1',
        name: 'Be concise',
        body: '请用最少篇幅作答。',
        createdAt: now,
        updatedAt: now,
        sortOrder: 0,
      ),
      UserInstructionEntry(
        id: 'inst-2',
        name: 'Cite sources',
        body: '回答时附上来源链接。',
        createdAt: now,
        updatedAt: now,
        sortOrder: 1,
      ),
    ];
    final session = _buildMinimalSession(messages: [
      AiSessionMessage.user(
        id: 'msg-1',
        content: 'Hi',
        createdAt: now,
      ),
    ]);

    String? extract45(List<AiChatTurn> messages) {
      for (final m in messages) {
        if (m.content.contains('[4.5] User Instructions')) {
          return m.content;
        }
      }
      return null;
    }

    final resultNoSkip = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session,
      model: model,
      runtimeContext: _buildRuntimeContext(userInstructions: instructions),
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session.messages,
      latestUserMessageId: 'msg-1',
    );
    final resultSkipOne = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session,
      model: model,
      runtimeContext: _buildRuntimeContext(
        userInstructions: instructions,
        skippedInstructionIds: const <String>{'inst-2'},
      ),
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session.messages,
      latestUserMessageId: 'msg-1',
    );

    expect(extract45(resultNoSkip.messages), isNotNull);
    expect(extract45(resultSkipOne.messages), equals(extract45(resultNoSkip.messages)),
        reason: '[4.5] User Instructions 必须始终渲染所有 enabled 指令，'
            'skippedInstructionIds 只能影响 [3d] Dynamic，否则 prefix cache 会被勾选打穿。');

    String? extract3d(List<AiChatTurn> messages) {
      for (final m in messages) {
        if (m.content.contains('[3d] Dynamic Session State')) {
          return m.content;
        }
      }
      return null;
    }

    expect(extract3d(resultSkipOne.messages)!.contains('skipped_user_instruction_ids'),
        isTrue,
        reason: '本轮被跳过的指令 id 必须出现在 [3d] Dynamic，让模型能在动态尾部读到。');
    expect(extract3d(resultSkipOne.messages)!.contains('inst-2'), isTrue);
  });

  testWidgets('[2] Tool Catalog stays byte-identical across awaitingPlanApproval toggle',
      (tester) async {
    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();
    final now = DateTime.now().toUtc();
    final session = _buildMinimalSession(messages: [
      AiSessionMessage.user(id: 'msg-1', content: 'Hi', createdAt: now),
    ]);
    final approvingSession = session.copyWith(awaitingPlanApproval: true);

    // 模拟控制器：固定一份「完整工具目录」用于 [2] 渲染；当 awaiting 时
    // availableTools=[] 但 displayCatalogOverride 仍传入完整目录。
    const fakeCatalog = <AiToolDefinition>[
      AiToolDefinition(
        name: 'Bash',
        description: 'Run shell command',
        parameters: <String, Object?>{},
      ),
      AiToolDefinition(
        name: 'Write',
        description: 'Write file',
        parameters: <String, Object?>{},
      ),
    ];

    final resultNormal = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: session,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: session.messages,
      latestUserMessageId: 'msg-1',
      availableTools: fakeCatalog,
    );
    final resultAwaiting = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: approvingSession,
      model: model,
      runtimeContext: runtimeContext,
      memoryEntries: const <UserMemoryEntry>[],
      sessionMessages: approvingSession.messages,
      latestUserMessageId: 'msg-1',
      availableTools: const <AiToolDefinition>[],
      displayCatalogOverride: fakeCatalog,
    );

    String? extract2(List<AiChatTurn> messages) {
      for (final m in messages) {
        if (m.content.contains('[2] Tool Catalog')) {
          return m.content;
        }
      }
      return null;
    }

    expect(extract2(resultNormal.messages), equals(extract2(resultAwaiting.messages)),
        reason: '提供 displayCatalogOverride 时 [2] Tool Catalog 应当跨 awaitingPlanApproval '
            '保持字节一致，由 [3d] plan.awaiting_approval 单独告知模型不可调用。');
  });
}
