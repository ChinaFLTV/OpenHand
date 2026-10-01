# Qwen3.8 与 Ling 3.1 模型核查（2026-10-02）

## 数据口径

仅将已公开、可追溯的 API 限制写入有效配置。百炼服务、OpenRouter 路由、本地开源权重分别匹配；推荐采样值、服务端默认值、能力上限、部署扩展条件和发布计划分开保存。人民币价格保留原币单位，不换算为固定美元价格。知识截止、到期时间及未公开输出上限不推测。

## Qwen3.8 百炼服务

| 型号 | 输入 / 输出 | 上下文 / 最大回答 / 最大思考词元 | 思考控制 |
| --- | --- | --- | --- |
| Max、Max-0902、Max-2026-09-02 | 文本、图片、视频 / 文本 | 1000000 / 131072 / 262144 | 默认开启；low、medium、xhigh |
| Flash | 文本、图片、视频 / 文本 | 1000000 / 131072 / 262144 | 默认开启；low、medium、xhigh |
| 27B | 文本、图片、视频 / 文本 | 1000000 / 131072 / 262144 | 默认开启；low、medium、xhigh |
| 2.4T-A95B | 文本 / 文本 | 1000000 / 131072 / 131072 | 常开；low、medium、xhigh |
| Omni Flash | 文本、图片、音频、视频 / 文本 | 1000000 / 131072 / 未单列 | 默认开启；low、medium、xhigh，保留兼容取值映射 |
| Omni Flash Realtime | 文本、音频、视频 / 文本、音频 | 最大输入 196608，最大输出 65536；未将输入上限冒充上下文 | 专用实时接口，未推断聊天思考参数 |

- 思考/非思考最大输入分别为 983616 / 991808（非实时模型）。2.4T 仅文本且思考常开，不再继承 27B 的视觉能力。
- 补全推理档位、互斥预算、默认值、采样范围、按模式的采样默认值、模型规模、区域能力、地区价格、缓存读写类型、限流条件及来源链接。
- 档位与预算互斥。关闭档位控制时保留手动 `thinking_budget`；显式指定档位时移除冲突预算。`minimal` 映射为 `low`，`high/max` 映射为 `xhigh`。纯思考模型拒绝关闭；其他型号关闭思考时清除残余推理参数。
- 官方兼容 API 给出的默认预算为 131072；xhigh 映射预算为 262144。2.4T 模型页单列思考上限为 131072，两种口径分别保留，不据档位映射扩大模型上限。
- Max、Flash 和 Omni 的历史思考回传使用独立 `reasoning_content` 与 `preserve_thinking`，关闭回传时显式发送 false。百炼 API 的回传支持清单与开源模板能力分开保存；不从本地模型卡推断百炼 27B/2.4T 的回传参数。
- Omni 联网搜索使用 `agent` 策略；仅输出文本，不附加音频生成能力。
- Realtime 保留两个地域的工作空间 WebSocket 地址、三种传输方式、56 个官方音色、默认 Tina、36 种输出语言/方言、音频声道与格式、视频聚合、媒体历史轮数/秒数、免费额度条件和分模态计价。它不能经普通 Chat Completions 调用，也不参与标题模型回退。此次补充规格，不新增 AOQ/WebRTC 传输实现。
- 收紧版本匹配，不再把 Flash-Next、未知后缀或未来日期型号套用为 Flash/Max 服务。

官方来源：

- [Max 与快照](https://help.aliyun.com/en/model-studio/qwen3-8-max)
- [Flash](https://help.aliyun.com/en/model-studio/qwen3-8-flash)
- [27B](https://help.aliyun.com/en/model-studio/qwen3-8-27b)
- [2.4T-A95B](https://help.aliyun.com/en/model-studio/qwen3-8-2-4t-a95b)
- [Chat Completions 参数](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions)
- [深度思考](https://help.aliyun.com/zh/model-studio/deep-thinking)
- [Omni Flash](https://help.aliyun.com/zh/model-studio/qwen3-8-omni-flash)、[调用指南](https://help.aliyun.com/zh/model-studio/qwen-omni)
- [Omni Realtime](https://help.aliyun.com/zh/model-studio/qwen3-8-omni-flash-realtime)、[接入指南](https://help.aliyun.com/zh/model-studio/realtime)、[音色](https://help.aliyun.com/zh/model-studio/omni-voice-list#qwen38-voices)
- [价格](https://help.aliyun.com/zh/model-studio/model-pricing#4c2e910ce4pcq)、[限流](https://help.aliyun.com/zh/model-studio/rate-limit#5b7c656e788u8)

## 开源权重与网关

[27B](https://huggingface.co/Qwen/Qwen3.8-27B)、[2.4T-A95B](https://huggingface.co/Qwen/Qwen3.8-2.4T-A95B)、[Flash-Next](https://huggingface.co/Qwen/Qwen3.8-Flash-Next) 及各自 FP8 版本共六种权重的官方 `config.json` 完整保存并按需解析，包含位置编码、架构与量化例外层。BF16 与 FP8 共用基座，量化配置独立保存。

原生窗口均为 262144；27B、Flash-Next 可扩展至 1000000，2.4T 模型卡写明可扩展至 1010000。应用不替服务端自动启用窗口扩展，也不把示例输出长度当作模型上限。思考开关和回传开关放入 `chat_template_kwargs`，档位仍使用顶层 `reasoning_effort`。推荐采样值与托管 API 默认值分离。

Flash-Next 的语言模型为 125B、激活 6B，另有 51B n-gram 嵌入与 4B MTP；分项保存，避免混淆规模口径。

通过 [OpenRouter 官方接口](https://openrouter.ai/api/v1/models) 核对当前 11 条 Qwen3.8 / Ling 3.x 在线记录，原始字段及序列化结果均与内置档案一致，无需改写网关目录。包括 Max Prime、免费版 27B、Ling 3.0 Flash/VL/Fin/Santé；历史下线条目保留。网关价格、强制思考和推理档位按网关记录处理，选择千问协议也不会错误注入百炼原生参数。

本轮目标记录快照 SHA-256：`f764bf41caf61058d95431aa1b368e7960c44480bbba7794ec3a23802a535a59`。

## Ling-3.1-flash：发布信息与 API 规格分开

[IT之家 9 月 30 日发布报道](https://www.ithome.com/1/008/907.htm) 列出约 560B 总参数、25B 激活参数、1M 模型窗口；免费体验两周，体验期服务窗口 256K，付费后计划提供 1M 服务并开源。

本次核查的[蚂蚁官方模型页](https://developer.ant-ling.com/zh-CN/docs/models/ling/)、[更新日志](https://developer.ant-ling.com/zh-CN/docs/getting-started/changelog/)、[API 文档](https://developer.ant-ling.com/zh-CN/docs/api-reference/openai/)、[价格页](https://developer.ant-ling.com/zh-CN/docs/models/price/) 仍只列至 Ling 3.0；Hugging Face 与 OpenRouter 未找到 Ling 3.1 条目。

因此新增的是带 `announcement_only` 标记的发布档案。256K/1M 保留原文，不猜测十进制/二进制换算；输出上限、思考开关、档位、价格、API 扩展参数、快照、知识截止和到期时间均不套用旧版本。编辑器明确显示“已发布 · API 规格待核实”和体验期条件，仍允许用户按实际提供商配置。

## 性能、交互与验证

- 复用已有分区卡片、窄屏换行、元数据延迟展开和全局弹窗进退场设置；未新增动画控制器，也未改动内置 Prompt。
- Qwen 档案按已知型号缓存，完整权重配置仅在首次使用相应型号时解析；切换或重绘不重复构建大对象。
- 元数据与协议 41 项（含 11 条网关快照逐字段、6 份原始权重配置完整比对）、编辑器 50 项、缓存 25 项、公共动画 18 项，共 134 项通过。
- 中文字体宽窄屏截图人工检查通过，包含新型号保存往返、未知规格提示、动画关闭和快速退场。修改文件静态分析通过。
- 提交前执行 `scripts/build_web.sh`，Web 构建与附带架构检查通过。未执行消耗额度的真实推理请求；发布报道不等于 API 实测可用。
