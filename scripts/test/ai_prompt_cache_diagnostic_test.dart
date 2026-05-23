import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

/// 综合缓存诊断：使用真实会话数据构建每轮 prompt，逐轮对比 API 消息。
///
/// 测试数据：/Users/liguanda/Downloads/一首歌的时间_*.jsonl
/// - 7 轮用户对话，27 条消息
/// - deepseek-v4-flash 模型，default 模板
/// - 包含 WebFetch 工具调用、推理（thinking）消息
void main() {
  final repo = AiPromptTemplateRepository();

  /// 从 JSONL 文件中解析会话消息。
  List<AiSessionMessage> _loadSessionMessages(String filePath) {
    final file = File(filePath);
    final lines = file.readAsLinesSync();
    final messages = <AiSessionMessage>[];
    for (final line in lines) {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) continue;
      if (decoded['type'] != 'message') continue;
      messages.add(AiSessionMessage.fromJson(decoded));
    }
    return messages;
  }

  AiSession _buildSession({
    required List<AiSessionMessage> messages,
    String title = 'Test Session',
  }) {
    final now = DateTime.now().toUtc();
    return AiSession(
      id: 'diag-session',
      title: title,
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
      memoryEntries: const [],
      workingDirectory: '/tmp/work',
      todayLocalDate: '2026-05-23',
      timeZoneName: 'Asia/Shanghai',
    );
  }

  /// 将 AiChatTurn 列表转换为 API 消息格式（含合并逻辑）。
  List<Map<String, Object?>> _toApiMessages(List<AiChatTurn> turns) {
    final rawMessages = turns.map((t) {
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
      if (t.role == AiChatRole.assistant) {
        final reasoning = t.reasoningContent;
        if (reasoning != null && reasoning.isNotEmpty) {
          payload['reasoning_content'] = reasoning;
        }
      }
      return payload;
    }).toList();

    // 合并连续 system 消息
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

  /// 查找消息列表中的第一个差异点并返回描述。
  String _findFirstDiff(
    List<Map<String, Object?>> prev,
    List<Map<String, Object?>> curr,
  ) {
    for (var i = 0; i < prev.length && i < curr.length; i++) {
      final p = prev[i];
      final c = curr[i];
      final pr = p['role'] as String;
      final cr = c['role'] as String;
      if (pr != cr) {
        return 'MSG $i: ROLE DIFFERS prev=$pr curr=$cr';
      }
      final pc = (p['content'] as String?) ?? '';
      final cc = (c['content'] as String?) ?? '';
      if (pc != cc) {
        var pos = 0;
        while (pos < pc.length && pos < cc.length && pc[pos] == cc[pos]) {
          pos++;
        }
        final ctx = pc.substring(
          (pos - 40).clamp(0, pc.length),
          (pos + 60).clamp(0, pc.length),
        );
        return 'MSG $i ($pr): CONTENT DIFFERS at byte $pos / ${pc.length} vs ${cc.length}\n'
            '  context: "${_escape(ctx)}"';
      }
      // Check tool_calls
      final ptc = p['tool_calls'];
      final ctc = c['tool_calls'];
      if (ptc != null || ctc != null) {
        if (jsonEncode(ptc) != jsonEncode(ctc)) {
          return 'MSG $i ($pr): TOOL_CALLS DIFFER';
        }
      }
      // Check reasoning_content
      final prc = p['reasoning_content'];
      final crc = c['reasoning_content'];
      if (prc != crc) {
        return 'MSG $i ($pr): REASONING_CONTENT DIFFERS';
      }
    }
    if (prev.length != curr.length) {
      return 'LENGTH DIFFERS: prev=${prev.length} curr=${curr.length}';
    }
    return 'ALL IDENTICAL';
  }

  /// 计算缓存命中率
  (int, int, int) _computeCacheStats(
    List<Map<String, Object?>> prev,
    List<Map<String, Object?>> curr,
  ) {
    var cachedChars = 0;
    var totalChars = 0;
    for (final m in curr) {
      totalChars += ((m['content'] as String?) ?? '').length;
    }
    for (var i = 0; i < prev.length && i < curr.length; i++) {
      final pc = (prev[i]['content'] as String?) ?? '';
      final cc = (curr[i]['content'] as String?) ?? '';
      if (pc == cc && prev[i]['role'] == curr[i]['role']) {
        final ptc = prev[i]['tool_calls'];
        final ctc = curr[i]['tool_calls'];
        final prc = prev[i]['reasoning_content'];
        final crc = curr[i]['reasoning_content'];
        if (jsonEncode(ptc) == jsonEncode(ctc) &&
            prc == crc) {
          cachedChars += cc.length;
        } else {
          break;
        }
      } else {
        break;
      }
    }
    final hitRate = totalChars > 0 ? (cachedChars * 100 ~/ totalChars) : 0;
    return (cachedChars, totalChars, hitRate);
  }

  testWidgets('Compare consecutive turns with real session data',
      (tester) async {
    const sessionFilePath =
        '/Users/liguanda/Downloads/一首歌的时间_0d7a657f-b7e0-45d5-800d-522e65d5b311.jsonl.jsonl';

    // Skip if the session file is not available.
    if (!File(sessionFilePath).existsSync()) {
      print('[SKIP] Session data file not found: $sessionFilePath');
      return;
    }

    final allMessages = _loadSessionMessages(sessionFilePath);
    expect(allMessages.length, greaterThanOrEqualTo(2),
        reason: '至少需要 2 条消息');

    final templateBundle = await repo.loadBundle('default');
    final model = _buildModel();
    final runtimeContext = _buildRuntimeContext();
    final builder = const AiPromptBuilder();

    // 收集所有用户消息 ID
    final userIds = allMessages
        .where((m) => m.kind == AiSessionMessageKind.user)
        .map((m) => m.id)
        .toList();

    print('\n========== CACHE DIAGNOSTIC (REAL DATA) ==========');
    print('Total messages: ${allMessages.length}');
    print('User turns: ${userIds.length}');
    print('User message IDs: ${userIds.map((id) => id.substring(0, 8)).join(', ')}');

    // 为每个用户轮次构建 prompt 并对比
    List<Map<String, Object?>>? prevApiMessages;
    var totalCachedChars = 0;
    var totalAllChars = 0;

    for (var t = 0; t < userIds.length; t++) {
      final latestId = userIds[t];
      // 模拟截止到当前轮次的会话消息
      final latestIndex = allMessages.indexWhere((m) => m.id == latestId);
      final sessionMessages = allMessages.sublist(0, latestIndex + 1);
      final session = _buildSession(messages: sessionMessages);

      final result = builder.buildSessionPrompt(
        templateBundle: templateBundle,
        session: session,
        model: model,
        runtimeContext: runtimeContext,
        memoryEntries: const [],
        sessionMessages: sessionMessages,
        latestUserMessageId: latestId,
      );

      final apiMessages = _toApiMessages(result.messages);

      if (prevApiMessages != null) {
        final (cachedChars, totalChars, hitRate) =
            _computeCacheStats(prevApiMessages, apiMessages);
        totalCachedChars += cachedChars;
        totalAllChars += totalChars;
        final diff = _findFirstDiff(prevApiMessages, apiMessages);
        print('\n--- Turn ${t + 1} vs Turn $t ---');
        print('Turn $t → Turn ${t + 1}: cached=$cachedChars total=$totalChars = $hitRate%');
        print('First diff: $diff');
      } else {
        final totalChars = apiMessages.fold<int>(
          0, (sum, m) => sum + ((m['content'] as String?) ?? '').length,
        );
        print('\n--- Turn ${t + 1} (baseline) ---');
        print('API messages: ${apiMessages.length}, total chars: $totalChars');
        // 打印每条消息的摘要
        for (var i = 0; i < apiMessages.length; i++) {
          final m = apiMessages[i];
          final role = m['role'] as String;
          final content = (m['content'] as String?) ?? '';
          final hasTC = m['tool_calls'] != null;
          final hasReasoning = m['reasoning_content'] != null;
          final extras = [
            if (hasTC) 'tool_calls',
            if (hasReasoning) 'reasoning',
          ].join(', ');
          print(
            '  MSG $i ($role${extras.isNotEmpty ? ", $extras" : ""}): ${content.length} chars — "${_escape(content.substring(0, (content.length < 80 ? content.length : 80).clamp(0, content.length)))}${content.length > 80 ? "..." : ""}"',
          );
        }
      }

      prevApiMessages = apiMessages;
    }

    final overallHitRate = totalAllChars > 0
        ? (totalCachedChars * 100 ~/ totalAllChars)
        : 0;
    print('\n================================================');
    print('OVERALL: $totalCachedChars / $totalAllChars chars = $overallHitRate% cache hit rate');
    print('Expected: high hit rate (>70%) between consecutive turns');
    print('================================================\n');
  });
}

String _escape(String s) {
  return s.replaceAll('\n', '\\n').replaceAll('\r', '\\r').replaceAll('\t', '\\t');
}
