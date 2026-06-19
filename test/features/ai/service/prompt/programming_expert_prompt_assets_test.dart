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
      expect(system, isNot(contains('`Edit`：精确替换')));
      expect(system, contains('`LSP`'));
      expect(system, isNot(contains('`Lsp`')));
      expect(system, contains('不要用普通文本请求计划批准'));
      expect(system, isNot(contains('用自然语言给出编号计划并请用户批准')));

      expect(developer, contains('<runtime_catalog>'));
      expect(developer, contains('<task_tool>'));
      expect(developer, contains('<file_operations>'));
      expect(developer, contains('`Task` 必须顶层传 `description`、`prompt`'));
      expect(developer, contains('省略时为 `general-purpose`'));
      expect(developer, contains('计划模式未获执行批准时省略 `Task.subagent_type`'));
      expect(developer, contains('Claude 规范名 `Agent`'));
      expect(developer, contains('`run_in_background`、`isolation`'));
      expect(developer, contains('`Edit`：精确替换'));
      expect(developer, contains('replace_all: true'));
      expect(developer, contains('本地文件路径可相对/绝对'));
      expect(developer, contains('相对路径按 cwd 解析'));
      expect(developer, contains('`LS`：列目录；`path` 可省略默认 cwd'));
      expect(developer, contains('`Write`：新文件'));
      expect(developer, contains('父目录会自动创建'));
      expect(developer, contains('旧 `target_file` 兼容'));
      expect(developer, contains('`NotebookEdit`：只用于 `.ipynb` 单元格'));
      expect(developer, contains('`notebook_path` 同样按 cwd 解析相对路径'));
      expect(developer, contains('`LSP`：类型化语言'));
      expect(developer, contains('Claude 风格 `filePath`'));
      expect(developer, contains('ToolSearch'));
      expect(developer, contains('select:<exact_name>'));
      expect(developer, contains('PDF 可传 Claude 风格 `pages`'));
      expect(developer, contains('会拒绝可能阻塞或无限输出的特殊设备路径'));
      expect(developer, contains('`verify` 子代理规则'));
      expect(developer, contains('VERDICT: PASS'));
      expect(developer, contains('tool_output_persisted_path'));
      expect(developer, contains('tool_output_recovery_hint'));
      expect(developer, contains('Claude 风格 `command`'));
      expect(developer, contains('run_in_background: true'));
      expect(developer, contains('dangerouslyDisableSandbox: true'));
      expect(developer, contains('`TaskOutput` / `TaskStop`'));
      expect(
        developer,
        contains('`BashOutputTool` / `AgentOutputTool` / `KillShell`'),
      );
      expect(developer, contains('Claude 旧名 `AskUserQuestion`'));
      expect(developer, contains('`multiSelect`、`preview`、`annotations`'));
      expect(developer, contains('不要用普通文本请求计划批准'));
      expect(developer, isNot(contains('按 schema 传绝对路径')));
      expect(developer, isNot(contains('只有用户明确要求才 commit')));
      expect(contextRecovery, contains('tool_output_truncated'));
      expect(contextRecovery, contains('tool_output_persisted_path'));
      expect(contextRecovery, contains('Task verify'));
    });
  });
}

String _readPrompt(String name) {
  return File('assets/prompts/programming_expert/$name').readAsStringSync();
}
