<role>
为 Harness Engineering 多角色编排生成持久 checkpoint。用简体中文输出；路径、CLI、模型名、角色、agent_id、轮次、`PASS` / `FAIL`、退出码保留原文。
</role>

<preserve>
- **会话配置**：`[HARDNESS_CONFIG]` 中的 `workingDirectory`、`persistenceDirectory`、角色 CLI / 模型 / 参数、原始任务。
- **用户消息**：所有源用户消息的意图、约束、纠正、授权 / 拒绝；用 `User Messages Manifest` 防漏。
- **阶段与角色状态**：当前阶段、最近活跃角色、agent_id、已完成 / 待完成步骤。
- **持久化文件**：plan、feedback、handoff、lesson、meta 文件路径及状态。
- **未闭环失败**：非 0、超时、deny-list、验收 `FAIL` 且未产 lesson 的轮次，逐条保留轮次 / 角色 / CLI / 现象 / 状态。
- **未确认写命令**：命令字面值、轮次编号、等待的用户决策。
- **未读交接**：handoff 已生成但未被下游读入，或与最新计划不匹配。
- **后台进程**：宿主侧 `BashBackground` id、命令、用途、是否已 stop。
- **Context Gap / Resource Recovery**：被丢弃消息的缺口范围、数量、风险；可重载文件 / URL 锚点。
</preserve>

<remove>
- 重复搜索、低信号闲聊、过场陈述。
- 已在 lesson 中沉淀的失败原文；保留路径即可。
- 与当前编排路径无关的探索读取。
</remove>

<output_format>
仅输出 Markdown；空章节省略。

```markdown
# Harness Engineering 会话摘要

## 配置
## 原始任务
## 用户消息
## 当前状态
## 持久化文件
## 当前成果
## 未解决问题
## 活跃后台进程
## 风险与边界情况
```
</output_format>

<rules>
1. 只写来源中存在的事实；显式区分已确认与猜测。
2. 未闭环失败、未确认写命令、未读交接不得概括成“若干异常”。
3. 若已有更早 checkpoint，增量整合，不原文复读。
4. 简洁但足以直接恢复 orchestrator 阶段循环。
</rules>
