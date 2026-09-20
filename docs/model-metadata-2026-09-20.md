# 模型元数据核验记录

核验日期：2026-09-20。目录中的参考参数不代表所有代理服务商的实际能力；运行时同步的精确资料和用户覆盖仍然优先。

| 用户指定模型 | 核验结果与处理 |
| --- | --- |
| Fable 5.2、Opus 5.2 | 官方目录当前列出 Fable 5.1、Opus 5，未找到 5.2 的正式规格。未知版本不套用旧版上下文、价格等数据；允许后续通过精确模型同步补充。 |
| GPT-6-Astra | 官方 ID 为 `gpt-6-astra`，上下文 1,050,000、最大输出 128,000；推理档位 low/medium/high/xhigh/max。清除官方不接受的采样字段，none/minimal 转为 low；官方工具调用必须使用 Responses。 |
| Gemini-3.8-Flash | 官方 ID 为 `gemini-3.8-flash`，输入上限 1,048,576、输出上限 65,536；推理档位 low/medium/high。不删除支持的采样参数；移除旧 thinking budget，将 minimal 调整为 low。 |
| Jev | 结构化决策模型，输入 state/questions，返回选择、评分或判断，不生成聊天文本。已接入专用决策接口与双端结构化配置、结果卡片；不作为标题模型，不发送普通聊天协议请求。 |

Jev 的 OpenRouter 固定版本 `typesafe/jev-1.13` 页面明确给出 32,000 上下文、每百万输入 token 0.042 美元、输出免费。原生固定版本 `jev-1.13.0` 的官方规格为每请求 64,000 token，状态加最长单个问题限 32,000，价格同为输入 0.042 美元、输出免费。两种固定 ID 分别记录限制；latest、preview 别名不固化移动版本的参数。未添加未经证实的知识截止日期和输出上限。

Fable 5.1 保留思考展示配置，以 adaptive 替代不支持的禁用/预算模式；强制工具调用调整为 auto。标题生成优先检查输出模态，避免把文本输入误认为文本输出。

## 核验来源

- [Claude 官方模型目录](https://platform.claude.com/docs/en/models/overview)
- [Fable 5.1 变更说明](https://platform.claude.com/docs/en/models/fable-5-1/whats-new-fable-5-1)
- [GPT-6 Astra 规格](https://developers.openai.com/api/docs/models/gpt-6-astra)
- [GPT-6 Astra 接口迁移说明](https://developers.openai.com/api/docs/guides/latest-model)
- [Gemini 3.8 Flash 规格](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash)
- [Google Cloud 参数说明](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-8-flash)
- [TypeSafe 模型说明](https://docs.typesafe.ai/models)
- [Jev 1.13 网关规格](https://openrouter.ai/typesafe/jev-1.13)

## 验证入口

`dart run scripts/check_model_metadata.dart` 覆盖版本误匹配、动态资料优先级、参数兼容、Jev 用途限制和标题输出模态判断。

## Jev 接入方式

- 原生服务：Base URL `https://api.typesafe.ai/v1`，Bearer 鉴权，协议选择 OpenAI，模型使用服务商提供的精确 ID（例如 `jev-1.13.0`）。实际调用 `/v1/systemone`，不会发送聊天协议字段。
- OpenRouter：Base URL `https://openrouter.ai/api/v1`，模型 `typesafe/jev-1.13`；实际调用 `/api/alpha/decisions`。自定义网关可覆盖 `decisions` 端点。
- App 和 Web 选中 Jev 后，输入区可配置判断、选择或评分。直接输入陈述时默认评估成立概率；带 `state/questions` 的完整 JSON 可批量配置问题，复杂配置重新打开时保留 JSON。
- 结果卡片展示答案、概率分布及接口实际返回的置信度，原始结构随消息保存。配置弹窗沿用全局进退场动效。
- 请求可取消，有超时及大小限制；失败不会改发聊天接口或自动重复计费请求。附件须先转成文本。
- 专用接口依据 [TypeSafe API](https://docs.typesafe.ai/api) 与 [OpenRouter 决策示例](https://openrouter.ai/labs/jev/compile)。模型扫描兼容 TypeSafe 的 `models/name` 目录格式。

`dart run scripts/check_decisions.dart` 验证实际服务路由、合成流、取消、模型扫描、响应校验和窄屏弹窗。Web 开发服务器的 `/tests/decisions.html` 验证真实卡片、配置及退出动画。测试使用合成响应，不代表已完成带真实凭据的在线调用。
