# Sol、Claude 5.5 与 Gemini 4 Argon 核查（2026-10-02）

## 核验口径

直接获取官方型号页、迁移指南、缓存及思考文档，再与 OpenRouter 在线模型接口交叉核对。原生 API、网关、发布公告分别保存；未公开参数留空，不能由评测规模、旧版本或模型名称推断能力。价格均为美元/百万词元，工具调用费用另计。

## 原生型号

| 型号 | 上下文 / 最大输入 / 最大输出 | 输入 / 输出 / 缓存读 / 缓存写 | 默认推理 |
| --- | --- | --- | --- |
| GPT-6 Sol | 1050000 / 922000 / 128000 | 2 / 10 / 0.2 / 2.5（OpenAI 写入 TTL 为 30 分钟） | medium，允许 none |
| GPT-6.1 Sol | 1050000 / 922000 / 128000 | 2 / 10 / 0.1 / 2.5（OpenAI 写入 TTL 为 30 分钟） | medium，不允许 none/minimal |
| Claude Opus 5.5 | 1000000 / 未单列 / 128000 | 4 / 20 / 0.2 / 5 | medium，自适应思考常开 |
| Claude Sonnet 5.5 | 1000000 / 未单列 / 128000 | 2 / 10 / 0.2 / 2.5 | high，adaptive 或 between_tools |

OpenAI 的缓存写价格不与 Claude 的 5 分钟 TTL 混用。Claude 1 小时缓存写分别为 8 / 4。知识截止日期依次为 2026-04-20、2026-04-30、2026-06、2026-06。Claude 的发布时间分别为 9 月 22 日和 9 月 28 日，最早退役日期均为一年后。

### Sol

- 保留文本/图像输入、文本输出、端点支持和拒绝清单、Responses 工具、五级 RPM/TPM、Sol Batch 队列上限、地域条件及服务等级倍率。
- 超过 272000 输入词元时，整次请求的输入与缓存价格乘 2，输出乘 1.5；区域处理乘 1.1，Fast 乘 2，Batch/Flex 乘 0.5。EU Fast 不可用。
- 缓存最小可见输入为 1024；默认 implicit，也支持 explicit；TTL 仅 30m，每次最多 4 次写入，implicit 占其中一个位置。预热通过 Responses；cache key 用于分开计费，不要求为命中率新增 key。
- 官方 Chat Completions：Sol 的函数调用仅在 none 档位可用；6.1 Sol 不支持工具调用，需用 Responses。不为接口错误自动伪装请求。
- 对附加参数中的未知推理档位明确报错；既有 none/minimal 兼容映射保留。保留合法扩展字段，不自动开启 beta、预热或付费模式。

来源：[Sol](https://developers.openai.com/api/docs/models/gpt-6-sol)、[6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol)、[GPT-6 指南](https://developers.openai.com/api/docs/guides/latest-model)、[缓存指南](https://developers.openai.com/api/docs/guides/prompt-caching)。

### Claude 5.5

- 补齐发布状态、计费单位、Models API 查询入口、无需窗口 beta、输出上限包含思考、结构化输出、严格工具调用及逐消息 effort 信息。
- between_tools 仅接受 type 字段，最大 effort 为 high，不支持逐消息改变 effort，也不接受 block_binding。保留既有请求规范化；思考展示显式使用 summarized，避免工具间进度在默认 omitted 下不可见。
- 思考块绑定 system/tools/messages；指定平台的新账户自 2026-08-31T00:00:00Z 起执行检查。记录 error/drop_block 选项及其 beta；不能用展示摘要重建原始签名块。本次不宣称实现完整签名持久化回放。
- Claude API/Google Cloud 使用 computer_toolset_20260801；Bedrock 保留 computer_20251124，不自动替换工具协议。
- Sonnet 记录思考的账户绑定、Opus 5.5 可读其思考的平台，以及七个允许的 advisor 型号和加密结果类型。其他平台兼容性未推断。
- 保留 Batch beta 300000 输出、缓存最低 512、Opus Fast 预览价格与 beta、Opus 不支持预填及 Priority Tier 等已有规格。

来源：[Opus](https://platform.claude.com/docs/en/models/opus-5-5/overview)、[迁移](https://platform.claude.com/docs/en/models/opus-5-5/migration-guide)、[Sonnet](https://platform.claude.com/docs/en/models/sonnet-5-5/overview)、[变化](https://platform.claude.com/docs/en/models/sonnet-5-5/whats-new-sonnet-5-5)、[Effort](https://platform.claude.com/docs/en/build-with-claude/effort)、[思考保留](https://platform.claude.com/docs/en/build-with-claude/preserved-thinking)。

## Gemini 4 Argon

[Google 9 月 30 日正式公告](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-4-argon/)与[DeepMind 型号主页](https://deepmind.google/models/gemini/)已确认发布。此结果更新了 10 月 1 日“尚未找到发布资料”的核验结论。

- 公告明确说 **最大输出为 1M**，不是最大输入或上下文窗口。保留原文，不把评测中的 1M 输入规模当作 API 上限。
- 首发输入/输出为 2 / 10，缓存输入比输入价低 95%；首发期后输入/输出为 4 / 20。期限及后续缓存价格未公开，不能固定为当前通用单价。
- 目前通过 Fairwind 向受信任网络安全防御者逐步开放，公开发布计划从付费 API 客户和 Google AI Ultra 订阅者开始；具体时间未给出。
- 保留长程推理、编程、企业知识工作、视觉/长视频理解及防御能力的公告信息，并记录 DeepMind 的 19 项评测分数与范围说明。评测分数不代表部署参数。
- [Gemini API 型号目录](https://ai.google.dev/gemini-api/docs/models)、[更新日志](https://ai.google.dev/gemini-api/docs/changelog)和 OpenRouter 本次返回未含 Argon。尝试的 Gemini API 与 Vertex 型号地址均 404。
- 新增 announcement_only 档案。`gemini-4-argon` 是应用中的识别名称，**未确认是正式 API ID**；有效输入/输出上限、思考档位、默认参数、缓存写价、知识截止、快照和有效固定单价留空。用户可按实际提供商资料手动配置。

## 版本与网关

四个原生型号未发布日期快照，不再仅凭日期格式继承其规格。精确内置网关记录和运行时同步资料仍优先；未知快照可以通过已核实的提供商资料配置。

本轮同步 10 条目标 OpenRouter 记录，包括在线 Pro/Batch 变体；保留其完整原始字段和历史下线记录。当前变化集中在评测元数据，原生与网关默认 effort、平台 ID、价格和工具参数分别保留。

目标快照 SHA-256：`2e377f9536f88e11862f373066ae5bf988e82050c2a028580324e9b3f6d71893`。

## 交互与验证

配置摘要增加独立最大输入标签，标明目录默认推理档位并提供提示；Argon 显示发布状态、公告输出及分阶段价格。复用换行布局、延迟元数据展开与全局进退场动画，不新增动画控制器或内置 Prompt。

元数据与请求 44 项、编辑器 52 项、缓存 25 项、动画 18 项，共 139 项回归通过；包含 10 条目标网关记录逐字段比对、未公开快照与非法档位、元数据往返、宽窄屏展示和保存、关闭全局动画及快速退场。修改文件静态分析通过，中文宽窄屏截图检查无布局重叠。

提交前执行 `bash scripts/build_web.sh`，类型检查、Web 运行时、交互、语音、产物及架构检查全部通过，重建产物与当前版本一致。未执行消耗额度的实际模型推理调用。
