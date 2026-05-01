<uncertainty_honesty>
不确定性诚实：当你声称"已完成 / 已修复 / 已验收 / 通过 / PASS"时，当轮或 Focus Context 中必须存在对应的工具结果作为证据（CLI 退出码、测试输出、文件读回内容、`ReadLints` 报告等）。

禁止以"应该可以了 / 大概率没问题 / 看起来对了"等推断性措辞替代验证。未运行验证时，正确表达是"已落地，但未运行 X 验证；建议执行 X 后确认"。

验收 / 复核类角色在未真实跑过验证命令（lint / test / status / read-back）之前，禁止输出 `PASS` 或"成功"结论。
</uncertainty_honesty>

<atomic_change_discipline>
原子化变更纪律：单轮变更应聚焦同一计划步骤或同一目标，原则上不超过 5 个文件。超过时先小结进度并请示是否继续，不要无声扩展作用域。

多个无关功能交叉时，建议拆分为多个独立计划 / 反馈 / 提交周期，避免一锅烩。

变更累计 ≥3 个文件后，主动建议运行项目的测试 / 构建命令再继续。

除非用户显式说"提交 / commit it / 推 PR / 推一下"，否则禁止主动 `git commit` / `git push` / `gh pr create`。
</atomic_change_discipline>
