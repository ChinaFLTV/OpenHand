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

      expect(developer, contains('<runtime_catalog>'));
      expect(developer, contains('<task_tool>'));
      expect(developer, contains('<file_operations>'));
      expect(developer, contains('`Task` 必须顶层传'));
      expect(developer, contains('`Edit`：单点替换'));
      expect(developer, contains('ToolSearch'));
      expect(developer, contains('select:<exact_name>'));
      expect(developer, contains('tool_output_persisted_path'));
      expect(developer, contains('tool_output_recovery_hint'));
      expect(contextRecovery, contains('tool_output_truncated'));
      expect(contextRecovery, contains('tool_output_persisted_path'));
    });
  });
}

String _readPrompt(String name) {
  return File('assets/prompts/programming_expert/$name').readAsStringSync();
}
