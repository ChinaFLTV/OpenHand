import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/bash/ai_bash_background_tool.dart';
import 'package:openhand/features/ai/tools/bash/ai_bash_tool.dart';

void main() {
  group('Bash Web Reverse CDP-first guard', () {
    test(
      'blocks target-origin Bash when Web Reverse CDP is unavailable',
      () async {
        final tool = AiBashTool(
          bashToolService: _FailingBashToolService(),
          hookService: AiNoopClaudeHookService(),
        );

        final result = await tool.execute(
          _context(
            toolName: 'Bash',
            arguments: const <String, Object?>{
              'cmd': 'curl https://linux.do/t/topic/2401043.json',
            },
            metadata: _unavailableWebReverseMetadata(),
          ),
        );

        expect(result.status, BashToolExecutionStatus.denied);
        expect(result.metadata['web_reverse_bash_blocked_for_cdp_first'], true);
        expect(
          result.metadata['web_reverse_cdp_route'],
          'runtime_unavailable_without_live_cdp',
        );
        expect(result.stderr, contains('Live CDP is unavailable'));
      },
    );

    test(
      'blocks target-origin BashBackground start before deny or spawn',
      () async {
        final tool = AiBashBackgroundTool(
          bashToolService: _FailingBashToolService(),
        );
        addTearDown(tool.dispose);

        final result = await tool.execute(
          _context(
            toolName: 'BashBackground',
            arguments: const <String, Object?>{
              'action': 'start',
              'cmd': 'curl https://linux.do/t/topic/2401043.json',
            },
            denyCommandRules: const <AiDenyCommandRule>[
              AiDenyCommandRule(
                id: 'deny-all-network-test',
                pattern: '*',
                matchMode: AiDenyCommandMatchMode.simple,
              ),
            ],
            metadata: _missingLocatorWebReverseMetadata(),
          ),
        );

        expect(result.status, BashToolExecutionStatus.denied);
        expect(result.matchedRulePattern, isNull);
        expect(
          result.metadata['web_reverse_bash_background_blocked_for_cdp_first'],
          true,
        );
        expect(
          result.metadata['web_reverse_bash_background_blocked_action'],
          'start',
        );
        expect(
          result.metadata['web_reverse_cdp_route'],
          'runtime_unavailable_without_live_cdp',
        );
      },
    );

    test('blocks target-origin BashBackground stdin write', () async {
      if (Platform.isWindows) return;

      final tool = AiBashBackgroundTool();
      addTearDown(tool.dispose);

      final start = await tool.execute(
        _context(
          toolName: 'BashBackground',
          arguments: const <String, Object?>{'action': 'start', 'cmd': 'cat'},
        ),
      );
      expect(start.status, BashToolExecutionStatus.success);
      final handle = '${start.metadata['bg_handle'] ?? ''}';
      expect(handle, isNotEmpty);

      final result = await tool.execute(
        _context(
          toolName: 'BashBackground',
          arguments: <String, Object?>{
            'action': 'write',
            'handle': handle,
            'input': 'fetch("https://linux.do/t/topic/2401043.json")',
          },
          metadata: _liveWebReverseMetadata(),
        ),
      );

      expect(result.status, BashToolExecutionStatus.denied);
      expect(
        result.metadata['web_reverse_bash_background_blocked_for_cdp_first'],
        true,
      );
      expect(
        result.metadata['web_reverse_bash_background_blocked_action'],
        'write',
      );
      expect(result.metadata['bg_handle'], handle);
    });
  });
}

AiToolExecutionContext _context({
  required String toolName,
  required Map<String, Object?> arguments,
  Map<String, Object?> metadata = const <String, Object?>{},
  List<AiDenyCommandRule> denyCommandRules = const <AiDenyCommandRule>[],
}) {
  return AiToolExecutionContext(
    sessionId: 'session-web-reverse-bash',
    catalog: _catalog(toolName),
    toolCall: AiToolCall(
      id: 'call-$toolName',
      name: toolName,
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _model,
    previouslyReadFiles: const <String>{},
    denyCommandRules: denyCommandRules,
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
    metadata: metadata,
  );
}

AiResolvedToolCatalog _catalog(String toolName) {
  final kind = toolName == 'BashBackground'
      ? AiBuiltinToolKind.bashBackground
      : AiBuiltinToolKind.bash;
  final definition = AiToolDefinition(
    name: toolName,
    description: 'Run a shell command.',
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'cmd': <String, Object?>{'type': 'string'},
        'action': <String, Object?>{'type': 'string'},
      },
    },
  );
  return AiResolvedToolCatalog(
    definitions: <AiToolDefinition>[definition],
    toolsByName: <String, AiResolvedTool>{
      toolName: AiResolvedTool(
        name: toolName,
        definition: definition,
        source: AiRuntimeToolSource.builtin,
        builtinKind: kind,
      ),
    },
  );
}

Map<String, Object?> _liveWebReverseMetadata() {
  return <String, Object?>{
    'web_reverse_runtime': <String, Object?>{
      'cdp_first_required': true,
      'config': <String, Object?>{
        'target_url': 'https://linux.do/t/topic/2401043/5',
      },
      'cdp_runtime': <String, Object?>{'browser_alive': true, 'cdp_port': 9223},
      'cdp_mcp_tool_availability': <String, Object?>{
        'browser_runtime_live': true,
        'current_turn_callable': true,
        'current_turn_callable_names': <String>[
          'mcp__web_reverse_cdp__evaluate_script',
        ],
      },
    },
  };
}

Map<String, Object?> _unavailableWebReverseMetadata() {
  return const <String, Object?>{
    'web_reverse_config': <String, Object?>{
      'target_url': 'https://linux.do/t/topic/2401043/5',
    },
    'web_reverse_cdp_runtime': <String, Object?>{
      'browser_alive': false,
      'last_cdp_port': 9223,
    },
  };
}

Map<String, Object?> _missingLocatorWebReverseMetadata() {
  return const <String, Object?>{
    'web_reverse_config': <String, Object?>{
      'target_url': 'https://linux.do/t/topic/2401043/5',
    },
    'web_reverse_cdp_runtime': <String, Object?>{'browser_alive': true},
  };
}

const _model = AiModelConfig(
  id: 'test',
  baseUrl: 'https://example.invalid',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

class _FailingBashToolService extends AiBashToolService {
  @override
  Future<BashToolExecutionResult> execute({
    required String command,
    String? sessionId,
    String? workingDirectory,
    required List<AiDenyCommandRule> denyRules,
    required bool requireWriteConfirmation,
    Future<BashCommandApprovalDecision> Function(
      BashCommandApprovalRequest request,
    )?
    confirmWriteCommand,
    void Function(BashToolExecutionUpdate update)? onUpdate,
    Future<void>? cancelSignal,
    int timeoutMs = AiBashToolService.defaultTimeoutMs,
    String? toolCallId,
    bool dangerouslyDisableSandbox = false,
  }) {
    throw StateError('Bash CDP-first guard did not block before dispatch.');
  }
}
