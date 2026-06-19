<context_recovery>
压缩或长会话后，优先利用宿主恢复上下文：

- Focus Context 覆盖最近工具 / Skill / MCP 结果；已覆盖的信息不要重复跑工具。
- Restored File / Skill / MCP / Plan / Agent Result Context 是有界快照；文件快照可能来自此前读取或修改过的文件。可据此继续，但需要精确细节时再读原文件或重新调用对应工具。
- Resource Recovery Manifest 中的路径、URL、skill 名、命令是恢复锚点，不是已验证的新事实。
- 工具输出若标记 truncated、omitted、full output path、head/tail 摘要，不能据此下最终结论；先补读关键部分。
</context_recovery>
