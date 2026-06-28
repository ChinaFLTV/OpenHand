import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';

void main() {
  test('parses todo items from json text without trimming content', () {
    final item = AiSessionTodoItem.fromJson(
      jsonEncode(<String, Object?>{
        'id': 7,
        'content': ' keep spacing ',
        'status': 'completed',
        'active_form': ' running ',
      }),
    );

    expect(item.id, '7');
    expect(item.content, ' keep spacing ');
    expect(item.status, 'completed');
    expect(item.activeForm, 'running');
  });

  test('parses allowed prompts from json text and filters invalid entries', () {
    final prompts = AiSessionPlanAllowedPrompt.listFromJson(
      jsonEncode(<Object?>[
        <String, Object?>{'tool': ' Bash ', 'prompt': ' run tests '},
        <String, Object?>{'tool': ' ', 'prompt': 'missing tool'},
        <String, Object?>{'tool': 'Edit', 'prompt': ''},
        'ignored',
      ]),
    );

    expect(prompts, hasLength(1));
    expect(prompts.single.tool, 'Bash');
    expect(prompts.single.prompt, 'run tests');
  });

  test('parses plan records with json text child lists', () {
    final record = AiSessionPlanRecord.fromJson(<String, Object?>{
      'id': 'plan-1',
      'created_at': '2026-06-28T01:00:00Z',
      'updated_at': '2026-06-28T02:00:00Z',
      'status': 'pending_approval',
      'plan': '  harden parsing  ',
      'steps': jsonEncode(<Object?>[
        <String, Object?>{
          'id': 'step-1',
          'content': 'implement',
          'status': 'in_progress',
        },
      ]),
      'allowed_prompts': jsonEncode(<Object?>[
        <String, Object?>{'tool': 'Shell', 'prompt': 'flutter test'},
      ]),
    });

    expect(record.id, 'plan-1');
    expect(record.createdAt, DateTime.parse('2026-06-28T01:00:00Z'));
    expect(record.updatedAt, DateTime.parse('2026-06-28T02:00:00Z'));
    expect(record.status, AiSessionPlanStatus.pendingApproval);
    expect(record.plan, 'harden parsing');
    expect(record.steps.single.id, 'step-1');
    expect(record.allowedPrompts.single.tool, 'Shell');
  });

  test('parses environment from json text with numeric fallbacks', () {
    final parsed = AiSessionEnvironment.fromJson(
      jsonEncode(<String, Object?>{
        'locale_tag': ' zh-Hans ',
        'platform': 'macos',
        'compression_threshold_chars': '4096',
        'single_round_tool_call_limit': '8',
        'sequential_tool_round_limit': '12',
      }),
    );

    expect(parsed.localeTag, 'zh-Hans');
    expect(parsed.compressionThresholdChars, 4096);
    expect(parsed.singleRoundToolCallLimit, 8);
    expect(parsed.sequentialToolRoundLimit, 12);

    final fallback = AiSessionEnvironment.fromJson(<String, Object?>{
      'compression_threshold_chars': '-1',
      'single_round_tool_call_limit': 0,
      'sequential_tool_round_limit': '-2',
    });

    expect(fallback.compressionThresholdChars, 0);
    expect(
      fallback.singleRoundToolCallLimit,
      AiSessionEnvironment.defaultSingleRoundToolCallLimit,
    );
    expect(
      fallback.sequentialToolRoundLimit,
      AiSessionEnvironment.defaultSequentialToolRoundLimit,
    );
  });

  test('parses error records from json text and drops blank detail', () {
    final record = AiSessionErrorRecord.fromJson(
      jsonEncode(<String, Object?>{
        'id': 11,
        'created_at': '2026-06-28T03:00:00Z',
        'stage': ' runtime ',
        'message': ' failed ',
        'detail': ' ',
        'presented_at': '2026-06-28T04:00:00Z',
      }),
    );

    expect(record.id, '11');
    expect(record.createdAt, DateTime.parse('2026-06-28T03:00:00Z'));
    expect(record.stage, 'runtime');
    expect(record.message, 'failed');
    expect(record.detail, isNull);
    expect(record.presentedAt, DateTime.parse('2026-06-28T04:00:00Z'));
  });
}
