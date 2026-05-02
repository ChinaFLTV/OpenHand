# OpenHand 上下文压缩机制研究与改造方案

日期：2026-05-03

## 1. 研究范围

本方案基于两部分源码阅读：

- Claude Code restored source：`/Users/liguanda/Public/VSCodeProjects/claude-code-sourcemap/restored-src`
- OpenHand 当前工程：`/Users/liguanda/Public/FlutterProjects/OpenHand`

目标不是照搬 Claude Code 的内部实现，而是提炼其稳定原则，映射到 OpenHand 现有架构中，形成可分阶段落地的上下文压缩体系。

## 2. Claude Code 的上下文压缩实现原理

### 2.1 核心模块

Claude Code 的上下文压缩集中在 `src/services/compact/` 与 `src/services/SessionMemory/`：

| 文件 | 职责 |
|---|---|
| `compact/autoCompact.ts` | 自动压缩触发、token 阈值、警告状态、电路断路器 |
| `compact/compact.ts` | 完整压缩主流程：预处理、摘要请求、PTL 重试、后置附件恢复 |
| `compact/prompt.ts` | 完整/部分压缩提示词、`<analysis>` 草稿剥离、摘要消息包装 |
| `compact/grouping.ts` | 按 API round 分组，保护 tool_use/tool_result 边界 |
| `compact/sessionMemoryCompact.ts` | 会话记忆优先压缩、尾部消息保留策略、API invariant 修复 |
| `compact/microCompact.ts` | 旧工具结果微压缩、cache-editing、时间基清理 |
| `utils/context.ts` | 模型上下文窗口、1M context、compact output token reserve |

### 2.2 触发与阈值

Claude Code 先计算“有效上下文窗口”：

```text
effective_context_window = model_context_window - min(model_max_output_tokens, 20000)
```

关键阈值：

| 阈值 | 值 | 作用 |
|---|---:|---|
| `MAX_OUTPUT_TOKENS_FOR_SUMMARY` | 20000 tokens | 给摘要输出预留空间 |
| `AUTOCOMPACT_BUFFER_TOKENS` | 13000 tokens | 自动压缩触发前的安全余量 |
| `WARNING_THRESHOLD_BUFFER_TOKENS` | 20000 tokens | UI 警告区间 |
| `ERROR_THRESHOLD_BUFFER_TOKENS` | 20000 tokens | UI 错误区间 |
| `MANUAL_COMPACT_BUFFER_TOKENS` | 3000 tokens | 手动压缩/阻塞限制余量 |

自动压缩触发条件：

- 当前消息 token 估算超过 `getAutoCompactThreshold(model)`。
- 用户/环境没有关闭 compact 或 auto compact。
- 当前 querySource 不是 `session_memory`、`compact` 等会导致递归或死锁的来源。
- 未被 reactive compact、context collapse 等更高优先级实验策略接管。
- 连续失败次数小于 3，超过后电路断路器停止自动重试。

### 2.3 完整压缩主流程

`compactConversation()` 的主干是：

1. 统计压缩前 token。
2. 执行 `PreCompact` hooks。
3. 构造无工具摘要请求。
4. 对待摘要消息做降噪：图片和文档替换为 `[image]` / `[document]`，可重注入的 skill discovery/listing 从摘要输入中剥离。
5. 调模型生成摘要。
6. 若摘要请求自身触发 prompt-too-long，调用 `truncateHeadForPTLRetry()` 丢弃最早 API round 后重试，最多 3 次。
7. 恢复压缩后的必要上下文：最近访问文件、异步 agent 附件、plan mode、skill invoked 状态、deferred tools、agent listing、MCP instruction delta、SessionStart hooks。
8. 写入 `compact_boundary` 与压缩摘要消息。
9. 记录 telemetry，重置 prompt cache break baseline，执行 post-compact cleanup。

### 2.4 API round 分组

Claude Code 不按“用户轮次”切压缩窗口，而按 API round：

- 新 assistant response 的 `message.id` 变化时产生边界。
- 同一个 assistant id 的 thinking / tool_use / text 流式块留在同组。
- tool_result 在下一个 assistant round 前必须已配对，所以 API round 是天然安全边界。
- 对 malformed conversation，API 层的 tool pairing repair 再兜底。

这个设计解决了单个用户请求内 agentic loop 很长时无法细粒度压缩的问题。

### 2.5 Session memory compaction

Claude Code 会优先尝试 session memory compaction：

- 默认至少保留 10000 tokens。
- 至少保留 5 条含文本块的消息。
- 最多保留 40000 tokens。
- 根据 `lastSummarizedMessageId` 切分旧摘要与新尾部。
- `adjustIndexToPreserveAPIInvariants()` 会向前扩展 startIndex，避免切断 tool_use/tool_result 或同 id thinking block。

### 2.6 Micro compact

Claude Code 把压缩分层，不是所有压力都交给模型摘要：

- 对 FileRead/Bash/Grep/Glob/WebSearch/WebFetch/Edit/Write 等可压缩工具，旧结果可以被清理。
- 时间基微压缩在 server cache 冷掉后触发，保留最近 N 个工具结果，其余替换为 `[Old tool result content cleared]`。
- cache-editing 微压缩不改本地消息，而是在 API 层发送 cache edits，减少上下文但尽量保留 prompt cache 命中。

### 2.7 摘要提示词结构

Claude Code 的摘要提示词有几个稳定特征：

- 开头强约束：`TEXT ONLY. Do NOT call any tools.`
- 让模型先在 `<analysis>` 中逐条分析，再输出 `<summary>`。
- 宿主会剥离 `<analysis>`，只保留摘要。
- 输出结构固定，覆盖用户意图、技术概念、文件/代码、错误修复、问题解决、全部用户消息、待办、当前工作、下一步。
- 分完整摘要与 partial 摘要：partial 只总结最近片段，早期上下文保持原样。

### 2.8 可迁移原则

对 OpenHand 最有价值的不是具体 TypeScript，而是这些原则：

1. 压缩请求本身也可能超上下文，必须有 PTL 重试。
2. 压缩前先降噪，不要把图片、可重注入目录、重复工具发现内容送入摘要请求。
3. 按 API/tool round 切窗，不能切断工具调用和工具结果。
4. 摘要 prompt 必须无工具、短、结构化，不需要完整业务 system prompt。
5. 压缩要分层：工具结果微压缩、会话摘要、长期记忆/交接文档各管一层。
6. 压缩失败要有电路断路器，避免每轮都失败并浪费 API 调用。
7. 压缩后的第一轮必须重注入必要状态，否则模型会失忆：工具目录、MCP 指令、plan mode、最近文件/附件、运行态配置。

## 3. OpenHand 当前实现梳理

### 3.1 线程模板资产

OpenHand 目前有 5 个内置线程模板，每个模板都有三件套：

- `system_instructions.md`
- `developer_instructions.md`
- `compression_summary_instructions.md`

模板清单：

| 模板 | 路径 | 压缩特征 |
|---|---|---|
| `default` | `assets/prompts/default/` | 通用 Objective / Context / Decisions / Code Changes / Tool Outcomes 清单 |
| `programming_expert` | `assets/prompts/programming_expert/` | 编程接力，强调代码上下文、架构、计划、构建测试、Git 状态 |
| `machine_expert` | `assets/prompts/machine_expert/` | 终端交互专用，必须保留目标终端绑定、假成功历史、shell 状态、后台会话 |
| `hardness_engineering` | `assets/prompts/hardness_engineering/` | 多角色编排专用，必须保留配置、阶段、角色、持久化文件、未闭环失败 |
| `hermes_talker` | `assets/prompts/hermes_talker/` | default + memory/skill 操作记录，防止重复写入近似条目 |

### 3.2 通用线程压缩

通用压缩入口在 `lib/features/ai/ai_session_controller.dart`：

1. `_shouldCompressSessionHistory()` 统计 latest compression point 之后的 active conversation 字符数。
2. `_effectiveCompressionThresholdChars()` 取设置阈值与模型字符预算的较小值。
3. `_compressIfNeeded()` 从尾部保留最新消息，前部作为待压缩候选。
4. `_selectCompressionWindowForModelContext()` 用二分缩小待摘要窗口，避免摘要 prompt 估算超模型上下文。
5. `AiPromptBuilder.buildCompressionPrompt()` 构造三条消息：压缩 system、压缩 developer、user payload。
6. 模型返回后写入 `AiSessionMessage.compressionPoint`。
7. `AiSession.activeConversationMessages` 只保留最新 checkpoint 之后的消息，历史依靠 checkpoint 内容恢复。

### 3.3 工具结果压缩

工具结果压缩在 `lib/features/ai/service/ai_prompt_builder.dart`：

- `toolResultCompressionThresholdChars` 默认 1024。
- 超阈值后生成 `[tool_result_summary]`，保留工具名、状态、purpose、受影响路径、head/tail。
- 最新未被模型消费的工具结果不压缩，避免模型首次看到工具输出时丢关键信息。
- 写文件类工具输出改为 `[write_result]`，保留 mutation、target、working directory、reason、短结果摘要，省略大 payload。

### 3.4 Hardness handoff

Hardness API phase runner 有独立交接压缩：

- 超过 `0.85 * min(settings threshold, model budget)` 时触发。
- 调模型生成 handoff markdown。
- 持久化到 `steering/handoff/handoff-{phase}-s{n}-{timestamp}.md`。
- 新 conversation 以 handoff + phase prompt 继续执行。
- 生成失败或空内容时退化为 `_trimConversationFallback()`。

## 4. 已确认问题与本轮修复

### 4.1 已确认问题

1. 消息压缩阈值只有默认值，没有 min/max。设置文件或 UI 输入极大值会让压缩长期不触发。
2. 工具输出压缩阈值虽然定义了 min/max，但设置文件读取时只判断正数，没有 clamp。
3. v4 discipline 去重使用字符串 contains，标题层级或空格变体可能导致重复注入。
4. 通用压缩 prompt 对多数模板会回灌完整 system instructions，摘要请求 token 成本偏高。
5. 通用压缩只在构造前估算 prompt 是否 fit；如果真实 API 仍报 prompt too long，会直接失败，没有 Claude Code 式缩窗重试。
6. `_selectCompressionWindowForModelContext()` 丢弃旧消息时只写 metadata，不会在 checkpoint content 里提醒后续模型存在未摘要断层。
7. Hardness handoff 只检查非空，低质量或格式漂移文档会被当成可接力上下文。

### 4.2 本轮已落地调整

| 类别 | 文件 | 调整 |
|---|---|---|
| 阈值边界 | `app_settings_snapshot.dart` | 新增消息压缩 min/max 与两个 normalize helper |
| 设置读取 | `settings_store.dart` | 读取 message/tool result compression threshold 时统一 clamp |
| 设置更新 | `settings_controller.dart` | controller 更新复用 normalize helper |
| 设置 UI | `settings_view.dart` | 保存后显示 clamp 后实际值 |
| 模板加载 | `ai_prompt_template_repository.dart` | v4 discipline 检测改为 markdown heading 正则 |
| 压缩 prompt | `ai_prompt_builder.dart` | 所有模板使用短身份 + TEXT ONLY + 禁工具压缩 system prompt |
| 通用压缩 | `ai_session_controller.dart` | API prompt-too-long 时最多 3 次丢弃最旧 20% 待摘要消息后重试 |
| 通用压缩 | `ai_session_controller.dart` | checkpoint content 记录 Context Gap，提醒有旧消息未纳入摘要 |
| Hardness | `hardness_api_phase_runner.dart` | handoff 生成后检查最小长度和关键 heading，不合格退化截断 |
| 测试 | `test/app/model/app_settings_snapshot_compression_test.dart` | 覆盖压缩阈值归一化 |
| 测试 | `test/features/ai/service/ai_prompt_builder_compression_test.dart` | 覆盖压缩 prompt 简洁无工具且不回灌完整 system |
| Phase 1 | `ai_session_controller.dart` / `_ai_session_models.dart` | 通用压缩窗口改为按消息组保留与压缩，PTL 重试也只丢完整组 |
| Phase 1 测试 | `test/features/ai/ai_session_controller_compression_group_test.dart` | 覆盖工具调用组分组与 PTL 重试整组丢弃 |
| Phase 2 | `ai_prompt_builder.dart` | 已消费旧工具结果 micro compact：只保留最近 5 个完整结果，更旧结果替换为极简清理摘要 |
| Phase 2 测试 | `test/features/ai/service/ai_prompt_builder_compression_test.dart` | 覆盖旧工具结果被清理、最近结果仍保留原文 |
| Phase 3 | `ai_prompt_builder.dart` / `_home_session_metadata_dialog.dart` | 写入上下文预算估算元数据，并在会话元数据弹窗展示预算状态、估算 token、剩余 token 与使用率 |
| Phase 3 测试 | `test/features/ai/service/ai_prompt_builder_compression_test.dart` | 覆盖 prompt build 输出上下文预算元数据 |
| Phase 4 | `hardness_api_phase_runner.dart` | handoff system prompt 对齐会话摘要结构，校验关键章节正文，保存同名 JSON sidecar 元数据 |
| Phase 4 测试 | `test/features/hardness/hardness_handoff_validation_test.dart` | 覆盖新旧 handoff 标题兼容、缺章节与空正文拒绝 |
| Phase 5 | `test/features/ai/service/ai_prompt_template_repository_test.dart` | 守护 5 个线程模板三件套真实资产加载、压缩说明结构、共享注入块去重 |
| Claude 对齐增强 | `ai_prompt_builder.dart` / `ai_session_controller.dart` | 上下文预算改为 summary reserve + auto-compact/warning/blocking buffer 语义；自动压缩连续失败 3 次后熔断；压缩后尾部保留至少 5 条文本锚点 |

## 5. OpenHand 目标架构

### 5.1 分层压缩

建议最终形成四层：

| 层级 | 名称 | 触发 | 是否调模型 | 主要目标 |
|---|---|---|---|---|
| L0 | Tool Result Compression | 单个工具结果超阈值 | 否 | 压缩长 stdout/read/web 输出 |
| L1 | Micro Compact | 旧工具结果累计膨胀或长时间未活动 | 否 | 清理已被消费的旧工具结果，保留最近 N 个 |
| L2 | Thread Checkpoint | active conversation 超阈值 | 是 | 生成模板专用 checkpoint |
| L3 | Durable Handoff / Memory | Hardness 阶段或跨线程接力 | 是 | 生成可持久化交接文档或长期记忆 |

现状已有 L0、L2、Hardness L3。本轮增强了 L2 的 prompt 与失败韧性。后续重点是补 L1 与更可靠的 L2 窗口安全。

### 5.2 压缩预算模型

短期继续用字符估算，长期应统一到 token budget：

```text
effective_window_tokens = model_context_tokens - min(model_max_output_tokens, 20000)
auto_compact_threshold = effective_window_tokens - 13000
warning_threshold = auto_compact_threshold - 20000
blocking_threshold = effective_window_tokens - 3000
```

OpenHand 当前 model 配置只有 `maxContextTokens`，没有所有协议的可靠 `maxOutputTokens`。建议新增：

- `AiModelConfig.maxOutputTokensForCompression`，无值时默认 20000。
- `AiContextBudgetEstimator`，集中做 chars/tokens 换算、阈值、警告状态。
- 会话元数据记录每次压缩前后的估算 token、字符数、压缩比例、丢弃数量。

### 5.3 压缩窗口切分

当前 `_compressIfNeeded()` 只按字符从尾部保留最近消息，可能切断 toolCall/toolResult 组。建议下一阶段改成“消息组”级别：

1. 扫描 active conversation。
2. 将连续 `toolCall` + 对应 `tool/mcp/skill` 结果归为一个 tool exchange group。
3. 将 reasoning + assistant/toolCall 同一轮归组。
4. 压缩窗口、保留窗口、PTL retry 都只在 group 边界移动。
5. 若遇到孤立工具结果，保留最小必要前驱，或者丢弃整个 malformed group 并写 Context Gap。

这样可以对齐 Claude Code 的 API round 分组思想，同时适配 OpenHand 自己的 `AiSessionMessageKind` 模型。

### 5.4 压缩提示词策略

建议保留当前“三件套资产”模型，但压缩请求不要使用完整 system instructions。最终规范：

- system turn：固定短身份、禁工具、禁止编造、只根据 payload。
- developer turn：模板专属 `compression_summary_instructions.md`。
- user turn：JSON payload + previous checkpoint + messages to compress。
- 不把完整 tool catalog、MCP、技能、普通 developer instructions 放进压缩请求。
- 输出始终 Markdown；如未来需要更强校验，可改成 `analysis` + `summary` 双块并在宿主剥离 analysis。

### 5.5 压缩后上下文恢复

Claude Code 在压缩后重注入多类附件。OpenHand 已有 Focus Context，但还可以增强：

- checkpoint content 中显式保留最近 active tools/MCP/skills 的状态摘要。
- 如果最近用户消息含图片，checkpoint 应保留 attachment id、图片摘要、原路径/存储路径。
- 压缩后首轮 prompt 的 `# [5.5] Focus Context` 应包含“压缩刚发生”的状态提示，避免模型误以为这是新线程。
- 对 Hardness，handoff 文件路径应写回 main session checkpoint 或阶段状态，便于 UI 和后续模型引用。

### 5.6 失败韧性

建议引入会话级压缩失败状态：

- `compression_consecutive_failures`。
- 连续 3 次后停止自动压缩，只记录错误并提示用户手动降低阈值或换大上下文模型。
- prompt-too-long 重试只丢 group，不丢单条消息。
- 所有丢弃都写入 checkpoint 的 Context Gap，至少记录数量、时间范围、kind 分布、是否未摘要。

## 6. 后续实施细则

### Phase 1：窗口安全与测试补齐

优先级：高

状态：已在 2026-05-03 继续落地第一版；后续仍可追加更细的端到端 fake chat client 测试。

1. 新增 `_CompressionMessageGroup`，在 `ai_session_controller.dart` 内部使用，避免拆出过多文件。
2. 将保留窗口和压缩窗口从“按单条消息”改为“按 group”。
3. PTL retry 改为丢弃最旧 group 的 20%，而不是最旧单条消息的 20%。
4. 新增测试：
   - toolCall + tool result 不被切断。
   - reasoning + toolCall 同轮不被切断。
   - prompt-too-long 连续两次后第三次成功。
   - prompt-too-long 超过 3 次后记录错误，不无限重试。

### Phase 2：L1 Micro Compact

优先级：中高

状态：已在 2026-05-03 落地第一版；当前仅处理标准 `tool` 结果，MCP / Skill / Hook 结果保持原逻辑。

1. 在 prompt builder 前增加历史工具结果 micro compact 预处理，仅处理“已被模型消费”的旧结果。
2. 默认保留最近 5 个工具 exchange 的完整结果。
3. 旧结果替换为 `[old_tool_result_cleared]`，保留 tool name、status、target、original chars。
4. 对 Read/Grep/WebFetch/Bash 分别调整 path/purpose 提取，降低误判。
5. 设置项只暴露开关和保留数量，不暴露复杂内部策略。

### Phase 3：Token Budget 与警告 UI

优先级：中

状态：已在 2026-05-03 落地第一版；当前使用字符 / 4 的轻量估算，只在会话元数据弹窗展示，不主动打断发送流程。

补充：后续已将预算状态改为更接近 Claude Code 的阈值语义：summary reserve、auto-compact buffer、warning/error buffer、manual blocking buffer 分开记录。

1. 新增 `AiContextBudgetSnapshot`：当前估算 tokens、剩余百分比、warning/error/autocompact 状态。
2. 在 session metadata dialog 与 top bar 显示上下文剩余状态。
3. 将 compression threshold 设置从“字符”逐步迁移为“自动 / 字符 / token”三种模式。
4. 对支持 usage 的协议优先使用真实 token usage，对不支持的协议使用字符估算。

### Phase 4：Hardness Handoff 增强

优先级：中

状态：已在 2026-05-03 落地第一版；当前记录 sidecar 元数据并阻断结构不完整的 handoff，尚未接入 session error 持久化。

1. 将 `_handoffSystemPrompt` 与 `assets/prompts/hardness_engineering/compression_summary_instructions.md` 对齐，避免两套清单漂移。
2. handoff 校验从 heading 检查升级为必填段落 + 关键字段检查。
3. 保存 handoff 时写 sidecar metadata：phase、source turn count、source chars、validation result、model id。
4. 交接失败时不要只做 silent trim：向 session error 记录结构化失败原因。

### Phase 5：模板资产守护

优先级：中

状态：已在 2026-05-03 落地第一版；当前以单元测试守护资产加载、压缩说明结构和 v4 / Memory Tone 去重。

1. 新增模板加载测试：5 个模板三件套都能从 asset 加载，且不落入 fallback。
2. 验证每个 compression summary 至少包含 preserve/remove/output_format/rules 或模板等价结构。
3. 验证每个 system instructions 不重复注入 Memory Tone Policy 与 v4 discipline。
4. 将 `scripts/preview_prompts.dart` 输出纳入人工审阅流程。

### 后续 Claude Code 对齐增强

已补充两项更接近 Claude Code 原生行为的保护：

1. **上下文预算阈值拆分**：预算元数据不再只按固定百分比标记 warning / critical，而是记录 `summary_reserve_tokens`、`effective_window_tokens`、`auto_compact_threshold_tokens`、`warning_threshold_tokens`、`error_threshold_tokens`、`blocking_limit_tokens` 与 `percent_left`。
2. **自动压缩熔断**：同一会话自动压缩连续失败 3 次后跳过后续自动压缩尝试，避免 prompt-too-long 或服务端异常导致每轮都重复发起必失败的压缩请求；下一次成功压缩会清除该计数。
3. **保留尾部文本锚点**：通用压缩在字符阈值外增加“至少保留 5 条用户 / 助手文本消息”的软约束，并用 2 倍阈值作为硬上限，避免压缩后只剩工具结果而缺少可恢复语义。

## 7. Prompt 维护准则

所有内置压缩提示词后续修改遵循：

1. 短 system，强 developer，payload 清晰。
2. 每个模板只保留本模板“真正不能丢”的状态，不把普通工作流规则塞进压缩提示。
3. 清单用名词短语，少写解释性长句。
4. 输出格式固定，空章节省略。
5. 不要求模型输出完整代码块，除非该代码片段是继续任务所必需。
6. 明确“已确认 / 猜测 / 待问”，避免摘要把不确定内容写成事实。

## 8. 验收标准

近期验收：

- `flutter analyze` 0 issues。
- `flutter test` 全部通过。
- 设置阈值低于 min / 高于 max 会被 clamp。
- 压缩 prompt 不包含完整模板 system instructions。
- 压缩请求 PTL 时最多 3 次重试，不无限失败循环。
- Hardness handoff 低质量输出不会直接进入接力会话。

中期验收：

- 通用压缩不会切断工具调用组。
- 工具结果 micro compact 能显著降低 prompt 字符数，且最新未消费结果保持原文。
- UI 能显示上下文剩余百分比与压缩状态。
- 5 个模板的 compression summary 都有测试守护。