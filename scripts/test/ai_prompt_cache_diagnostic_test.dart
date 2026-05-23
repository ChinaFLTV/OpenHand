import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

/// Diagnostic test: builds prompts for two consecutive turns and compares
/// the final API messages to find what breaks the prefix cache.
void main() {
  final repo = AiPromptTemplateRepository();

  AiSession _sessionWithMessages(List<AiSessionMessage> messages) {
    final now = DateTime.utc(2026, 5, 23, 12, 0);
    return AiSession(
      id: 'diag-session',
      title: 'Cache Diagnostic',
      templateId: 'default',
      templateName: 'Default Assistant',
      templateIconName: 'auto_awesome_rounded',
      templateInternalVersion: '3.0.0',
      createdAt: now,
      updatedAt: now,
      messages: messages,
      environment: const AiSessionEnvironment(
        localeTag: 'zh-CN',
        platform: 'macos',
        appVersion: '1.0.0',
        appBuildNumber: '1',
        applicationDirectory: '/tmp/diag',
        homeDirectory: '/tmp/diag',
        settingsFilePath: '/tmp/diag/settings.json',
        skillsStoragePath: '/tmp/diag/skills',
        mcpServersFilePath: '/tmp/diag/mcp.json',
        userMemoryFilePath: '/tmp/diag/memory.json',
        sessionsDirectoryPath: '/tmp/diag/sessions',
        compressionThresholdChars: 100000,
      ),
      statistics: const AiSessionStatistics.initial(),
      recentErrors: const <AiSessionErrorRecord>[],
    );
  }

  AiModelConfig _model() {
    return AiModelConfig(
      id: 'diag-model',
      baseUrl: 'https://api.example.com',
      authScheme: AiAuthScheme.bearer,
      token: 'test-token',
      modelId: 'deepseek-v4-flash',
      protocolType: AiProtocolType.openai,
    );
  }

  AiSessionRuntimeContext _runtimeContext() {
    return AiSessionRuntimeContext(
      localeTag: 'zh-CN',
      appVersion: '1.0.0',
      appBuildNumber: '1',
      settingsFilePath: '/tmp/diag/settings.json',
      skillsStoragePath: '/tmp/diag/skills',
      mcpServersFilePath: '/tmp/diag/mcp.json',
      userMemoryFilePath: '/tmp/diag/memory.json',
      compressionThresholdChars: 100000,
      memoryEnabled: false,
      memoryEntries: const [],
      workingDirectory: '/tmp/diag',
      todayLocalDate: '2026-05-23',
      timeZoneName: 'Asia/Shanghai',
    );
  }

  /// Converts AiChatTurn list to the final API messages array (with merging).
  List<Map<String, Object?>> _toApiMessages(List<AiChatTurn> turns) {
    final rawMessages = turns
        .map((t) {
          // Simplified _mapOpenAiMessage logic
          final payload = <String, Object?>{'role': t.roleName};
          if (t.role == AiChatRole.tool) {
            payload['tool_call_id'] = t.toolCallId ?? '';
            payload['content'] = t.content;
            return payload;
          }
          payload['content'] = t.content;
          if (t.role == AiChatRole.assistant && t.toolCalls.isNotEmpty) {
            payload['tool_calls'] =
                t.toolCalls.map((tc) => tc.toOpenAiJson()).toList();
          }
          return payload;
        })
        .toList();

    // Simulate _mergeConsecutiveSystemMessages
    final merged = <Map<String, Object?>>[];
    StringBuffer? pendingSystem;
    for (final msg in rawMessages) {
      if (msg['role'] == 'system' && msg['content'] is String) {
        pendingSystem ??= StringBuffer();
        if (pendingSystem.isNotEmpty) pendingSystem.write('\n\n');
        pendingSystem.write(msg['content'] as String);
      } else {
        if (pendingSystem != null) {
          merged.add(<String, Object?>{
            'role': 'system',
            'content': pendingSystem.toString(),
          });
          pendingSystem = null;
        }
        merged.add(msg);
      }
    }
    if (pendingSystem != null) {
      merged.add(<String, Object?>{
        'role': 'system',
        'content': pendingSystem.toString(),
      });
    }
    return merged;
  }

  testWidgets('Cache diagnostic: compare consecutive turn prompts',
      (tester) async {
    final templateBundle = await repo.loadBundle('default');
    final builder = const AiPromptBuilder();

    // Build a simulated multi-turn conversation
    final msg1 = AiSessionMessage.user(
      id: 'msg-1',
      content: '能不能给我一首歌的时间？',
      createdAt: DateTime.utc(2026, 5, 23, 12, 7, 1),
    );

    // Simulate turn 1: only 1 message, no history
    final turn1Messages = <AiSessionMessage>[msg1];
    final turn1Session = _sessionWithMessages(turn1Messages);

    final turn1Result = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: turn1Session,
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const [],
      sessionMessages: turn1Messages,
      latestUserMessageId: 'msg-1',
    );

    final turn1ApiMessages = _toApiMessages(turn1Result.messages);

    // Simulate assistant response to turn 1
    final msg2 = AiSessionMessage(
      id: 'msg-2',
      kind: AiSessionMessageKind.assistant,
      role: AiSessionMessageRole.assistant,
      content: '一首歌的时间？现在整晚都是你的。别浪费。',
      createdAt: DateTime.utc(2026, 5, 23, 12, 7, 33),
      characterCount: '一首歌的时间？现在整晚都是你的。别浪费。'.length,
    );

    // Turn 2: user sends a new message
    final msg3 = AiSessionMessage.user(
      id: 'msg-3',
      content: '那给我输出一下给我一首歌的时间的歌词吧！',
      createdAt: DateTime.utc(2026, 5, 23, 12, 7, 35),
    );

    final turn2Messages = <AiSessionMessage>[msg1, msg2, msg3];
    final turn2Session = _sessionWithMessages(turn2Messages);

    final turn2Result = builder.buildSessionPrompt(
      templateBundle: templateBundle,
      session: turn2Session,
      model: _model(),
      runtimeContext: _runtimeContext(),
      memoryEntries: const [],
      sessionMessages: turn2Messages,
      latestUserMessageId: 'msg-3',
    );

    final turn2ApiMessages = _toApiMessages(turn2Result.messages);

    // ── COMPARISON ──
    print('\n========== CACHE DIAGNOSTIC ==========');
    print('Turn 1 API messages: ${turn1ApiMessages.length}');
    print('Turn 2 API messages: ${turn2ApiMessages.length}');

    for (var i = 0;
        i < turn1ApiMessages.length && i < turn2ApiMessages.length;
        i++) {
      final m1 = turn1ApiMessages[i];
      final m2 = turn2ApiMessages[i];
      final r1 = m1['role'] as String;
      final r2 = m2['role'] as String;
      final c1 = (m1['content'] as String?) ?? '';
      final c2 = (m2['content'] as String?) ?? '';

      if (r1 != r2) {
        print('MSG $i: ROLE DIFFERS! Turn1=$r1 Turn2=$r2');
        break;
      }
      if (c1 != c2) {
        // Find the exact byte position of the first difference
        var diffPos = 0;
        while (diffPos < c1.length &&
            diffPos < c2.length &&
            c1[diffPos] == c2[diffPos]) {
          diffPos++;
        }
        final context1 = c1.substring(
          diffPos.clamp(0, c1.length),
          (diffPos + 100).clamp(0, c1.length),
        );
        final context2 = c2.substring(
          diffPos.clamp(0, c2.length),
          (diffPos + 100).clamp(0, c2.length),
        );
        print(
            'MSG $i ($r1): CONTENT DIFFERS at byte $diffPos / ${c1.length} vs ${c2.length} chars');
        print('  Turn 1 @ $diffPos: "${_escape(context1)}"');
        print('  Turn 2 @ $diffPos: "${_escape(context2)}"');
        // Print a wider context window
        final start = (diffPos - 80).clamp(0, c1.length);
        final end = (diffPos + 80).clamp(0, c1.length);
        print('  Turn 1 context: "${_escape(c1.substring(start, end))}"');
        break;
      }
      print('MSG $i ($r1): SAME (${c1.length} chars)');
    }

    // Calculate cache hit rate
    var cachedChars = 0;
    var totalChars = 0;
    for (final m in turn2ApiMessages) {
      totalChars += ((m['content'] as String?) ?? '').length;
    }
    for (var i = 0;
        i < turn1ApiMessages.length && i < turn2ApiMessages.length;
        i++) {
      final c1 = (turn1ApiMessages[i]['content'] as String?) ?? '';
      final c2 = (turn2ApiMessages[i]['content'] as String?) ?? '';
      if (c1 == c2 &&
          turn1ApiMessages[i]['role'] == turn2ApiMessages[i]['role']) {
        cachedChars += c2.length;
      } else {
        break;
      }
    }
    final hitRate =
        totalChars > 0 ? (cachedChars / totalChars * 100).round() : 0;
    print(
        '\nCache: $cachedChars / $totalChars chars = $hitRate% hit rate');
    print('======================================\n');

    // If the first message (merged system) differs, print its full content
    // to help identify the diff
    if (turn1ApiMessages.isNotEmpty && turn2ApiMessages.isNotEmpty) {
      final c1 = (turn1ApiMessages[0]['content'] as String?) ?? '';
      final c2 = (turn2ApiMessages[0]['content'] as String?) ?? '';
      if (c1 != c2) {
        print('FIRST MERGED SYSTEM MESSAGE DIFFERS!');
        print('Turn 1 length: ${c1.length}');
        print('Turn 2 length: ${c2.length}');
        // Find first diff
        var pos = 0;
        while (pos < c1.length && pos < c2.length && c1[pos] == c2[pos]) {
          pos++;
        }
        print('First diff at byte $pos');
        print(
            'Turn 1 from diff: "${_escape(c1.substring(pos, (pos + 200).clamp(0, c1.length)))}"');
        print(
            'Turn 2 from diff: "${_escape(c2.substring(pos, (pos + 200).clamp(0, c2.length)))}"');
      }
    }
  });
}

String _escape(String s) {
  return s.replaceAll('\n', '\\n').replaceAll('\r', '\\r').replaceAll('\t', '\\t');
}
