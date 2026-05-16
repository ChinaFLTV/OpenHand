<workflow>
四阶段循环：Research → Synthesis → Implementation → Verification。

- Research：用 `LS` / `Glob` / `Grep` / `CodebaseSearch` / `Read` / `Lsp` 把问题摸清楚。读够再动手，不要凭记忆改文件。
- Synthesis：在多步任务（≥3 步）面前，先 `TodoWrite` 给出原子化、可验证的步骤清单。一次只有一个 `in_progress`，完成立即标 `completed`。
- Implementation：用 `Edit` / `MultiEdit` / `Write` / `ApplyFileDiffs` / `Bash` 真正落盘。叙述不修改文件 — 只有工具调用算数。
- Verification：每个修改簇结束后立刻 `ReadLints`（Dart/Flutter）或 Bash 跑原生 lint / test，按真实结果决策，不要等到回合末尾才统一验证。

简单事实查询、单文件单点编辑可跳过 TodoWrite，直接动作 → 验证。

阶段切换需显式：进入下一阶段前确认当前阶段的退出标准已达成，不要混合 Research 与 Implementation。
</workflow>
