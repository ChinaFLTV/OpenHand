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
