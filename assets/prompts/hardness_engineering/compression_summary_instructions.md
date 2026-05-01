# Hardness Engineering - 压缩摘要指令

在压缩 Hardness Engineering 会话历史时，请保留以下信息，并确保压缩后的摘要全文使用简体中文。只有代码、命令、路径、文件名、模型名、CLI 名称、`PASS` / `FAIL` 等技术标识可以保留原文。

## 必须保留（绝不能压缩掉）

1. **会话配置**：原始 `[HARDNESS_CONFIG]` 块中的以下内容：
   - 工作目录
   - 持久化目录
   - 所有角色的 CLI / 模型分配
   - 原始任务描述

2. **当前阶段与代理状态**：压缩发生时的阶段与角色

3. **持久化文件引用**：本次会话中写入的所有文件路径：
   - 已创建的计划文件
   - 已创建的反馈文件
   - 已创建的交接文件
   - 已创建的 lesson 文件

4. **未解决的失败项**：任何尚未解决的错误消息或 CLI 失败

5. **最新计划**：当前执行计划的完整内容（或该文件的路径引用）

## 压缩格式

```markdown
# Hardness Engineering 会话摘要

## 配置
- 工作目录：{path}
- 持久化目录：{path}
- 调查者：{cli} / {model}
- 规划者：{cli} / {model}
- 实施者：{cli} / {model}
- 验收者：{cli} / {model}

## 原始任务
{task description}

## 当前状态
- 阶段：{current_phase}
- 最近活跃角色：{role} ({agent_id})
- 已完成步骤：{list of completed plan steps}
- 待完成步骤：{list of remaining plan steps}

## 本次会话已创建的持久化文件
- 计划：{list of plan file paths}
- 反馈：{list of feedback file paths}
- 交接：{list of handoff file paths}
- Lessons：{list of lesson file paths}

## 当前成果
{brief description of what has been accomplished}

## 未解决问题
{any unresolved failures or blockers}
```

---

## 漏保护补充清单（HE 长会话压缩必保留）

以下条目一旦在压缩时被丢掉，下一轮无法继续推进或会重蹈覆辙——**禁止**概括为"曾出现若干异常"：

1. **CLI 失败但未产 lesson 的轮次**：CLI 退出非 0、超时、被 deny-list 拦截、或验收 FAIL 但 lesson 文件尚未写入的事件，必须逐条保留 `轮次 / 角色 / CLI / 失败现象 / 决议状态`，并显式标注"未闭环"。
2. **未确认的写命令**：deny-list 命中后用户尚未确认/拒绝的命令字面值与轮次编号——下一轮必须先恢复对话再决策。
3. **未结束的交接**：handoff 文件已生成但未被下游角色读入，或交接文档与最新计划版本不匹配的情形。
4. **角色独立性破例**：若 reviewing 阶段曾被迫读取实施者的内部推理（例如复制粘贴）也应保留事实陈述，避免后续轮次错以为始终保持了独立。
5. **当前活跃 BashBackground / 子进程**：若编排过程中起了任何宿主侧后台进程，记录其 `id` + 启动命令 + 用途 + 是否已 stop。

