# 模型目录核查记录（2026-09-30）

## 数据范围与口径

- 同步 [OpenRouter 官方模型接口](https://openrouter.ai/api/v1/models) 的 460 条在线记录，保留原始字段和历史型号；两个内置网关目录合计 573 个唯一 ID。
- 本次新增网关 ID：`anthropic/claude-sonnet-5.5`、`anthropic/claude-sonnet-5.5:batch`、`nex-agi/nex-n2.5-mini`、`nex-agi/nex-n2.5-pro`。
- 下载快照 SHA-256：`ebffd75afbe8a4c7a8a2fdaf0fa42d00b3e74901f7fd160c883ad7cc75c7c04a`。同步校验和测试逐项比较了全部在线记录的原始字段及序列化结果。
- 原生服务与网关规格分别匹配；地区、套餐、分时、缓存和媒体计价保留原始单位，不把人民币、积分或每秒价格写入美元词元单价。
- 最大输入、上下文、最大输出、推荐输出和独立思考预算分别记录。官方未公开或无法核实的字段留空；模型卡片、API 文档及网关记录不是付费调用成功的证明。

## 本次新增与校正

| 提供商 | 处理结果 | 官方依据 |
| --- | --- | --- |
| OpenAI | 新增 GPT-6.1 Sol；补充 GPT-6 Sol/Luna/Astra 的最大输入与长上下文价格条件；移除未经证明的独立思考上限；约束 Sol 6.1 工具调用接口 | [Sol 6.1](https://developers.openai.com/api/docs/models/gpt-6.1-sol)、[Sol](https://developers.openai.com/api/docs/models/gpt-6-sol)、[Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)、[Astra](https://developers.openai.com/api/docs/models/gpt-6-astra) |
| Anthropic | 新增 Sonnet 5.5，区分普通与批量输出上限；记录缓存门槛、知识截止、发布和最早退役时间；关闭前置思考时改用 between_tools，并限制强度 | [Sonnet 5.5](https://platform.claude.com/docs/en/models/sonnet-5-5/overview)、[变更](https://platform.claude.com/docs/en/models/sonnet-5-5/whats-new-sonnet-5-5)、[推理强度](https://platform.claude.com/docs/en/build-with-claude/effort) |
| Google | 新增 Transcribe 3.5 文件/实时、Omni 1.1/Preview、Lyria 3.5、Nano Banana 2 Lite；记录输入输出模态、时长、分辨率、音频格式和接口限制 | [转写](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe)、[视频](https://ai.google.dev/gemini-api/docs/models/gemini-omni-flash)、[音乐](https://ai.google.dev/gemini-api/docs/models/lyria-3.5)、[图片](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite-image) |
| Qwen | 新增 Qwen3.8-27B、2.4T-A95B 的百炼规格；补充 Max/Flash 的输入边界和来源；区分混合思考与纯思考模型 | [27B](https://help.aliyun.com/en/model-studio/qwen3-8-27b)、[2.4T](https://help.aliyun.com/en/model-studio/qwen3-8-2-4t-a95b)、[Max](https://help.aliyun.com/en/model-studio/qwen3-8-max)、[Flash](https://help.aliyun.com/en/model-studio/qwen3-8-flash) |
| Stepfun | 补充 Step 3.7 Flash 的真实默认值、支持参数、模型规模及来源；删除无法核实的 32768 输出上限；新增六种 StepAudio 3 型号，区分转写、理解、实时、语音和音乐生成 | [Step 3.7](https://platform.stepfun.com/docs/zh/guides/models/step-3.7-flash)、[聊天参数](https://platform.stepfun.com/docs/zh/api-reference/chat/chat-completion-create.md)、[音频目录](https://platform.stepfun.com/docs/zh/guides/models/audio.md) |
| Kimi | K3 最大输出修正为 1048576，默认 131072 单独保存；固定采样参数单独记录 | [K3 接口指南](https://platform.kimi.com/docs/guide/kimi-k3-quickstart) |
| MiniMax | 新增 M3.1 Flash Preview，保留套餐可用性和常开思考；补充五档强度并实际发送；推荐输出与最大输出分离，不继承 M3 的价格 | [OpenAI 兼容接口](https://platform.minimax.io/docs/api-reference/text-chat-openai)、[Anthropic 接口](https://platform.minimax.cn/docs/api-reference/text-anthropic-api) |
| Meta | 新增 Muse Spark 1.1/1.2/1.3 与两种 Contributor 型号、Muse Image、Muse Voice Transcribe；记录档位价格、训练数据条件、1.3 音频限制；移除 Llama 4 通用输出猜测值 | [模型](https://dev.meta.ai/docs/models)、[推理](https://dev.meta.ai/docs/reasoning)、[价格](https://dev.meta.ai/docs/pricing-rate-limits)、[Llama 4](https://huggingface.co/meta-llama/Llama-4-Maverick-17B-128E-Instruct) |
| Jev | latest/preview 对应 1.13.0 原生规格，64000 上下文与 32000 请求限制分别保存，保持专用决策协议 | [官方模型目录](https://docs.typesafe.ai/models) |
| Mistral | 新增 Medium 3.5 的正式 ID、256000 上下文及价格；未公开的输出上限留空 | [Medium 3.5](https://docs.mistral.ai/models/mistral-medium-3-5-26-04) |
| Hunyuan | 新增 HY Image v3.5 Preview/v3 图片模型，不套用聊天词元限制 | [TokenHub 模型目录](https://cloud.tencent.com/document/product/1823/130051) |
| xAI / SpaceXAI / Grok | 补充 Grok 4.7 规范 ID、知识截止和接口限制；网关记录随官方接口刷新 | [Grok 4.7](https://docs.x.ai/developers/models/grok-4.7) |

## 复核后保留的目录与限制

| 提供商 | 本轮核查结论 |
| --- | --- |
| DeepSeek | [官方定价](https://api-docs.deepseek.com/quick_start/pricing) 的 V4.1 Flash/V4 Pro 容量及分时定价已有对应档案；保持原生与网关价格分离。 |
| GLM | [官方模型概览](https://docs.bigmodel.cn/cn/guide/start/model-overview) 中 5.3 系列已有档案；保留常开思考约束。 |
| LongCat | [官方文档](https://longcat.chat/platform/docs/zh/) 的 2.5 Preview/2.0 已有档案，保留已有容量配置。 |
| 讯飞星火 | [Token Plan 文档](https://www.xfyun.cn/doc/spark/TokenPlan.html) 的 X2.5/X2 Flash 及积分单价已有档案；[spark-x](https://www.xfyun.cn/doc/spark/X1http.html) 的版本由端点决定，不能只凭模型 ID 固定为 X2。 |
| Seed / 豆包 | [9 月上线记录](https://docs.volcengine.com/docs/ark/coding-plan-personal-model-release?lang=zh) 确认 Seed 2.1 Pro/Lite 上线；已有日期型号保留。[完整模型列表](https://docs.volcengine.com/docs/ark/model-list?lang=zh) 本轮只返回脚本外壳，未把 Coding Plan 别名猜测为某个日期型号，也未宣称重新核实全部旧参数。 |
| Kling / 可灵 | [官方发布](https://ir.kuaishou.com/node/11216/pdf) 确认 3.0 系列。已有原生异步媒体档案保留；API 文档部分页面仅返回脚本外壳，本轮未增加无法核实的新版本或词元价格。 |
| 文心 / ERNIE | [千帆 API 文档](https://cloud.baidu.com/doc/qianfan-api/s/Dmba8k71y) 已检查；示例参数不视为所有部署的实际限制，已有原生与网关档案保留。 |

## 行为与界面

- 修复过宽的 TTS、图片和 Spark 名称匹配，避免跨厂商套用错误档案。
- 标题模型判断读取明确的输入输出模态，排除纯转写和纯媒体输出模型。
- 模型编辑器把词元限制、价格、来源参数分区；窄屏数值字段单列、宽屏双列，推理档位操作可换行。
- 原始元数据保持按需展开，复用全局弹窗进退场及展开动画，没有增加独立动画控制器或修改内置 Prompt。
- 新增专用媒体模型的目录记录不等于新增对应媒体传输实现；实时、视频及其他专用端点仍需匹配应用现有功能和服务商权限。

## 验证

目录同步一致性检查通过。模型元数据及请求体 29 项、宽窄屏与多语言编辑器 23 项、公共动画 18 项、请求缓存 25 项，共 95 项回归通过；修改文件静态分析无问题。提交前 `scripts/build_web.sh` 重建及其类型、运行时、交互和架构检查通过。未执行消耗额度的真实模型推理请求。
