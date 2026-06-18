<workflow>
四阶段循环：Research → Synthesis → Implementation → Verification。

- Research：用 `LS` / `Glob` / `Grep` / `CodebaseSearch` / `Read` / `Lsp` 把问题摸清楚。读够再动手，不要凭记忆改文件。
- Synthesis：多步任务（≥3 步）优先用目录中的 todo / plan 工具给出原子化、可验证清单；没有对应工具则用简短编号计划。
- Implementation：用目录中的编辑 / 命令工具真正落盘。叙述不修改文件 — 只有工具调用算数。
- Verification：每个修改簇结束后立刻 `ReadLints`（Dart/Flutter）或 Bash 跑原生 lint / test，按真实结果决策，不要等到回合末尾才统一验证。

小范围、低风险、可一次完成的任务可跳过 TodoWrite；完成后按需验证。

阶段切换需显式：进入下一阶段前确认当前阶段的退出标准已达成，不要混合 Research 与 Implementation。
</workflow>
