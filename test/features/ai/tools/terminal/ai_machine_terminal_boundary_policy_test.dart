import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/terminal/ai_machine_terminal_tools.dart';

void main() {
  group('机器终端会话边界策略', () {
    test('允许普通输入、引用文本与 Ctrl-C', () {
      for (final input in <String>[
        'uptime',
        'echo exit',
        "printf '%s' 'logout'",
        'echo "suspend"',
        '\x03',
      ]) {
        expect(
          AiMachineTerminalBoundaryPolicy.inputViolation(input),
          isNull,
          reason: input,
        );
      }
    });

    test('拒绝退出命令及其注释和重定向形式', () {
      for (final input in <String>[
        'exit',
        'exit 0 # 完成',
        'logout >/dev/null',
        'command suspend',
        'exec /bin/true',
        'command exec "\$SHELL"',
        'true; then exit 1; fi',
      ]) {
        expect(
          AiMachineTerminalBoundaryPolicy.inputViolation(input),
          isNotNull,
          reason: input,
        );
      }
    });

    test('拒绝断连控制字符、SSH 转义和终止 Shell 的命令', () {
      for (final input in <String>[
        '\x04',
        '\x1a',
        '\x1c',
        '\x1d',
        '~.',
        '\n  ~.',
        'kill -9 \$\$',
        'sudo /bin/kill \$PPID',
        'builtin kill \${PPID}',
      ]) {
        expect(
          AiMachineTerminalBoundaryPolicy.inputViolation(input),
          isNotNull,
          reason: input,
        );
      }
    });

    test('控制工具只允许清屏和调整尺寸', () {
      expect(
        AiMachineTerminalBoundaryPolicy.allowsControlAction('clear'),
        isTrue,
      );
      expect(
        AiMachineTerminalBoundaryPolicy.allowsControlAction(' RESIZE '),
        isTrue,
      );

      for (final action in <String>[
        'start',
        'stop',
        'restart',
        'new',
        'duplicate',
        'close',
        'restore',
        'delete',
        'select',
        'unknown',
      ]) {
        expect(
          AiMachineTerminalBoundaryPolicy.allowsControlAction(action),
          isFalse,
          reason: action,
        );
      }
    });
  });
}
