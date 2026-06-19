import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Programming Expert prompt assets', () {
    test('keep system prompt focused and tool manual in developer prompt', () {
      final system = _readPrompt('system_instructions.md');
      final developer = _readPrompt('developer_instructions.md');
      final contextRecovery = _readPrompt('sections/context_recovery.md');

      expect(system.split('\n').length, lessThanOrEqualTo(100));
      expect(system, isNot(contains('<tool_use>')));
      expect(system, isNot(contains('<task_tool>')));
      expect(system, isNot(contains('<file_editing>')));
      expect(system, isNot(contains('Task` 必须顶层传')));
      expect(system, isNot(contains('`Edit`：单点替换')));
      expect(system, contains('不要用普通文本请求计划批准'));
      expect(system, isNot(contains('用自然语言给出编号计划并请用户批准')));

      expect(developer, contains('<runtime_catalog>'));
      expect(developer, contains('<task_tool>'));
      expect(developer, contains('<file_operations>'));
      expect(developer, contains('`Task` 必须顶层传 `description`、`prompt`'));
      expect(developer, contains('省略时为 `general-purpose`'));
      expect(developer, contains('计划模式未获执行批准时省略 `Task.subagent_type`'));
      expect(developer, contains('`Edit`：单点替换'));
      expect(developer, contains('ToolSearch'));
      expect(developer, contains('select:<exact_name>'));
      expect(developer, contains('`verify` 子代理规则'));
      expect(developer, contains('VERDICT: PASS'));
      expect(developer, contains('tool_output_persisted_path'));
      expect(developer, contains('tool_output_recovery_hint'));
      expect(developer, contains('run_in_background: true'));
      expect(developer, contains('不要用普通文本请求计划批准'));
      expect(contextRecovery, contains('tool_output_truncated'));
      expect(contextRecovery, contains('tool_output_persisted_path'));
      expect(contextRecovery, contains('Task verify'));
    });
  });
}

String _readPrompt(String name) {
  return File('assets/prompts/programming_expert/$name').readAsStringSync();
}
