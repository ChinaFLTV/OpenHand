import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/hardness/hardness_api_phase_runner.dart';

void main() {
  test('accepts asset-aligned handoff summary', () {
    const content = '''# Hardness Engineering 会话摘要

## 配置
- 工作目录：/repo
- 持久化目录：/repo/.hardness

## 原始任务
用户要求完成上下文压缩 Phase 4，并保持现有阶段循环可接力执行。

## 当前状态
- 阶段：implementing
- 最近活跃角色：implementer (agent-1)
- 已完成步骤：增强 handoff prompt
- 待完成步骤：运行验证并提交

## 本次会话已创建的持久化文件
- 计划：/repo/.hardness/plan.md
- 反馈：暂无已确认事项
- 交接：暂无已确认事项
- Lessons：暂无已确认事项
- Meta：architecture.md 已就绪

## 当前成果
已将交接摘要格式对齐为可恢复的会话摘要，保留阶段、路径、失败项和风险。

## 未解决问题（含未闭环的 CLI 失败 / 未确认写命令 / 未读交接）
- 暂无已确认事项

## 活跃后台进程
- 暂无已确认事项

## 风险与边界情况
当前使用模型生成摘要，仍需依靠校验阻断结构不完整的输出。
''';

    expect(validateHardnessHandoffDocument(content), isNull);
  });

  test('accepts legacy handoff heading names', () {
    const content = '''# Hardness Engineering 交接文档

## 原始任务
用户要求完成上下文压缩 Phase 4，并保持现有阶段循环可接力执行。

## 当前进展
- 当前阶段：implementing
- 最后一次操作：增强校验逻辑

## 未完成事项
- 运行验证并提交改动

## 已知问题与风险
当前使用模型生成摘要，仍需依靠校验阻断结构不完整的输出。
''';

    expect(validateHardnessHandoffDocument(content), isNull);
  });

  test('rejects missing unresolved work section', () {
    const content = '''# Hardness Engineering 会话摘要

## 原始任务
用户要求完成上下文压缩 Phase 4，并保持现有阶段循环可接力执行。

## 当前状态
- 阶段：implementing
- 最近活跃角色：implementer (agent-1)

## 当前成果
已将交接摘要格式对齐为可恢复的会话摘要，保留阶段、路径、失败项和风险。

## 风险与边界情况
当前使用模型生成摘要，仍需依靠校验阻断结构不完整的输出。
''';

    expect(validateHardnessHandoffDocument(content), contains('未解决问题'));
  });

  test('rejects empty critical section bodies', () {
    const content = '''# Hardness Engineering 会话摘要

## 原始任务
用户要求完成上下文压缩 Phase 4，并保持现有阶段循环可接力执行。

## 当前状态
- 阶段：implementing

## 未解决问题（含未闭环的 CLI 失败 / 未确认写命令 / 未读交接）
-

## 风险与边界情况
当前使用模型生成摘要，仍需依靠校验阻断结构不完整的输出。
''';

    expect(validateHardnessHandoffDocument(content), contains('未解决问题'));
  });
}
