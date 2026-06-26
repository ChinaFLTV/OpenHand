import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  test('parses machine expert request prompt into display card metadata', () {
    final card = AiMachineExpertRequestCard.fromPrompt('''
- 终端应用：【iTerm2 (AppleScript 进程名为 iTerm)】
- 打开的终端位置：【窗口：liguanda@Mac:~，会话：~ (-zsh)】
- AppleScript 精确定位：【window 1 → tab 1 → session 1】
- 需求内容（工作环境是：用户在【终端应用】与【打开的终端位置】输入参数中共同指定的目标终端会话环境）：【检查 CPU 状态
并汇总关键进程】''');

    expect(card, isNotNull);
    expect(card!.terminalApplication, 'iTerm2 (AppleScript 进程名为 iTerm)');
    expect(card.terminalLocation, '窗口：liguanda@Mac:~，会话：~ (-zsh)');
    expect(card.appleScriptTarget, 'window 1 → tab 1 → session 1');
    expect(card.taskRequirement, '检查 CPU 状态\n并汇总关键进程');

    final restored = AiMachineExpertRequestCard.fromMetadata(card.toJson());
    expect(restored?.taskRequirement, card.taskRequirement);
  });

  test('ignores unrelated user prompts', () {
    expect(AiMachineExpertRequestCard.fromPrompt('帮我写一个脚本'), isNull);
    expect(AiMachineExpertRequestCard.fromPrompt('需求内容：【只是普通描述】'), isNull);
  });
}
