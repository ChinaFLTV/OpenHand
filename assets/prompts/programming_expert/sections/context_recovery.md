<context_recovery>
压缩或长会话后，优先利用宿主恢复上下文：

- Focus Context 覆盖最近工具 / Skill / MCP 结果；已覆盖的信息不要重复跑工具。
- Restored File / Skill / MCP / Plan / Subagent Result Context 是有界快照；文件快照可能来自此前读取或修改过的文件。可据此继续，但需要精确细节时再读原文件或重新调用对应工具。
- Resource Recovery Manifest 中的路径、URL、skill 名、命令是恢复锚点，不是已验证的新事实。
- 工具输出若有 `tool_output_truncated`、`tool_output_omitted_chars`、`tool_output_persisted_path` 或 head/tail 摘要，先判断缺口是否影响结论；影响就读 `tool_output_persisted_path`，无路径时缩小范围重跑。
- 若恢复上下文包含 `Task verify` / `VERDICT`，把它当作证据摘要；最终结论仍需核对命令、关键输出和当前工作区状态。
</context_recovery>
