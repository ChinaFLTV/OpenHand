# 会话导出后缀修复与流式消息丝滑化设计

## 背景

当前项目存在两个相互独立但都直接影响用户体感的问题：

1. 线程会话条目菜单中的“导出会话数据”在部分入口/平台上会得到双 `.jsonl` 后缀文件名，属于导出链路各层对文件扩展名处理不一致导致的重复补后缀问题。
2. 线程模板会话在 AI 持续流式输出期间，正在追加内容的消息卡片会随着增量文本到达出现整卡抖动、闪烁、硬刷新感，说明当前流式渲染链路在 delta 到达时仍会重建过大的 UI 子树，而不是把更新范围限制在文本局部。

本设计目标是在不破坏现有功能边界的前提下，统一修复 APP + Web 端的导出文件名问题，并将流式消息体验从“整卡刷新”改造成“局部文本自然追加，完成后无缝增强”。

## 设计目标

- 修复所有相关导出入口的双 `.jsonl` 问题。
- 统一 APP / Web / 服务端对导出文件名与扩展名的语义。
- 将 Flutter APP 与 Web 端流式消息统一为“轻流式 + 完成后增强”策略。
- 保持所有涉及弹窗、菜单、过渡动画与全局动画设置一致，不引入生硬硬切。
- 不做与本次问题无关的大范围重构。

## 已确认的根因

### 1. 导出文件名双后缀

Flutter APP 端多个入口当前直接把建议名拼成 `... .jsonl`：

- `lib/features/settings/widgets/thread_session_management_dialog.dart`
- `lib/features/home/openhand_home_page.dart`

这些入口本身没有“若已带 `.jsonl` 则去重”的统一规则。如果底层保存面板、调用方、平台文件选择器或上层输入再次追加扩展名，就会出现双后缀。

Web 端还存在额外不一致：

- `clients/web/src/api/sessions.ts:514` 当前 fallback 文件名为 `.json`
- `saveBlobWithPicker()` 的 accept 也按 `.json`
- 但 APP 端和导出语义本身都是 JSONL

这意味着 Web 的 fallback、服务端 `Content-Disposition`、浏览器保存 API 三层之间存在扩展名不一致，出现重复追加或错后缀只是时间问题。

服务端 `lib/features/message_gateway/service/web_message_platform_service.dart:4809` 负责生成 `Content-Disposition`，当前 fallback 仍偏向 `session.json` 风格，也需要统一到 `.jsonl` 语义。

### 2. Flutter APP 流式消息卡片抖动

当前 Flutter assistant 流式消息在：

- `lib/features/home/widgets/_home_message_bubble.dart:587`

走的是：

- `StreamingTextReveal(child: _AssistantMessageBodyDispatcher(...))`

`StreamingTextReveal` 只负责 reveal 视觉效果，但其 child 仍是完整富渲染分发树。每次 `data` 变长时，`_AssistantMessageBodyDispatcher` 及其下游 markdown / html / plain_text 分支、折叠判断、预览体、代码块、附件摘要等都有机会重建。

这会导致：

- 更新范围不是“新增加的文本”
- 而是“整块 assistant 消息内容 subtree”
- 最终表现为消息卡片整体晃动、闪烁、硬刷新感

### 3. Web 端流式消息存在相同风险

Web 端会话详情页：

- `clients/web/src/features/sessions/components/SessionDetailPage.tsx:3538`

将 streaming 状态传入：

- `clients/web/src/components/MessageCard.tsx`

当前需要进一步按实现拆出 streaming 分支，但从结构上已经可以确定：如果 Web 端也让 streaming 文本直接进入完整富渲染消息卡组件，就会出现与 Flutter 类似的“每次 delta 到达重跑过大渲染树”风险。因此本次设计要求 Web 端同步采用同策略，而不是只修 APP。

## 方案总览

### A. 导出链路统一文件名规范化

新增统一的文件名规范化规则，原则如下：

1. 先清洗基础名，移除路径分隔符、控制字符与不安全字符。
2. 识别目标扩展名 `.jsonl`（大小写不敏感）。
3. 若基础名已带 `.jsonl`，不再追加。
4. 若基础名不带 `.jsonl`，只追加一次。
5. 任何 APP / Web / 服务端导出入口都复用这一规则，而不是各自手写字符串拼接。

#### Flutter APP 端应用点

- `lib/features/home/openhand_home_page.dart`
- `lib/features/settings/widgets/thread_session_management_dialog.dart`

这些入口统一调用同一个 helper 生成建议文件名，避免不同入口各自拼接 `.jsonl`。

#### Web 端应用点

- `clients/web/src/api/sessions.ts`

修正点：

- fallback 默认文件名改为 `.jsonl`
- `saveBlobWithPicker` 的 accept 改为 JSONL
- 服务端响应头返回的文件名先做规范化再交给保存逻辑

#### 服务端应用点

- `lib/features/message_gateway/service/web_message_platform_service.dart`

修正 `Content-Disposition` 的 fallback 语义，使默认导出名也使用 `.jsonl`，并尽量保证与客户端规范一致。

### B. Flutter APP 端流式消息改为“两阶段渲染”

Flutter 端 assistant / reasoning 流式消息统一采用：

1. **Streaming 阶段：轻量渲染**
   - 使用专用轻量正文组件承接流式内容
   - 只做文本追加、局部 reveal、光标、单层高度平滑变化
   - 不在 streaming 期间做完整 markdown AST 富渲染

2. **Settled 阶段：完成后增强**
   - 当消息不再 streaming 后，再切换到现有 `_AssistantMessageBodyDispatcher`
   - 恢复 markdown、代码块、链接、附件、折叠预览等完整能力
   - 切换过程使用柔和淡入/尺寸对齐过渡，避免硬切

#### Flutter 端具体边界

- 外层消息气泡只保留一层主导高度动画。
- `StreamingTextReveal` 继续使用，但只包轻量正文，不再包完整富渲染树。
- 轻量正文尽量直接输出 plain text / lightweight text presentation，确保每个 delta 的 rebuild 面积足够小。
- 完成后才做昂贵 markdown 解析与复杂 widget 构建。

#### 为什么不用“实时全量富渲染”

因为当前问题本质不是 reveal 动画不够好，而是每次增量都让富渲染树重算。继续保留实时全量富渲染，只会把性能与稳定性押在更复杂的缓存/剪枝上，仍不如直接把 streaming 阶段职责收缩到“自然追加文本”稳妥。

### C. Web 端流式消息采用同策略

Web 端 `MessageCard` 在 streaming 时也拆成独立轻量分支：

1. **Streaming 阶段**
   - 使用轻量文本正文组件承接 AI 持续追加内容
   - 避免每次 token / delta 到达都触发完整 markdown / 富交互内容重新生成
   - 只做局部文本更新与柔和的尺寸/光标过渡

2. **Settled 阶段**
   - 流式完成后切回现有完整 MessageCard 富渲染内容
   - 保持最终展示能力与当前一致

这样 APP 与 Web 虽然不必共用组件实现，但会共用同一套交互策略：

- 流式中轻量
- 完成后增强
- 不让整卡在 streaming 期间频繁硬刷新

### D. 动画一致性要求

所有这次触达的 UI 都继续复用现有动画体系，不新增平行规范：

- 弹窗：`lib/shared/ui/animated_dialog.dart`
- 菜单：`lib/shared/ui/animated_menu.dart`
- 消息卡片高度/切换：现有 motion token 与曲线

约束如下：

- 不允许导出相关弹窗/菜单出现硬切
- 不允许流式内容同时由内外多层尺寸动画竞争
- 不允许流式完成切换到完整富渲染时整卡突变闪烁

## 详细改动边界

### Flutter APP

#### 导出

- `lib/features/home/openhand_home_page.dart`
  - 收敛 `_exportSession()` / `_exportHardnessSession()` 的建议文件名生成逻辑
- `lib/features/settings/widgets/thread_session_management_dialog.dart`
  - 收敛单个导出与批量导出的 `.jsonl` 文件名生成逻辑
- 视情况抽出共享 helper（优先放在已存在的 AI session export / shared util 相邻位置，避免过度拆散）

#### 流式消息

- `lib/features/home/widgets/_home_message_bubble.dart`
  - assistant streaming 分支改为轻量正文组件
- `lib/features/home/widgets/_home_message_content.dart`
  - 补充或新增 streaming 专用正文实现
- `lib/shared/ui/streaming_text_reveal.dart`
  - 只在必要时做小幅增强，不承担“减少重建范围”的职责

### Web

#### 导出

- `clients/web/src/api/sessions.ts`
  - 修复 fallback 扩展名、accept 类型、文件名规范化
- 如 `SessionsPage.tsx` / `SessionDetailPage.tsx` 需要，只保留调用侧传 basename，不再各自决定扩展名

#### 流式消息

- `clients/web/src/components/MessageCard.tsx`
  - 在 streaming 分支引入轻量正文
- `clients/web/src/features/sessions/components/SessionDetailPage.tsx`
  - 保持当前 streaming 标记传递方式，但让下游渲染分支真正区分 streaming / settled

### 服务端

- `lib/features/message_gateway/service/web_message_platform_service.dart`
  - 统一 `Content-Disposition` fallback 文件名扩展名语义为 `.jsonl`

## 测试与验证方案

### 1. 导出文件名验证

Flutter APP：

- 主页线程会话导出
- 线程会话管理弹窗中的单个导出
- 批量导出

Web：

- 会话列表页导出
- 会话详情页导出

验证点：

- 结果文件名只带一个 `.jsonl`
- fallback 与服务端返回名一致语义
- 不再出现 `.json` / `.jsonl` 混用

### 2. 流式消息体验验证

Flutter APP：

- 线程模板会话中发送可稳定产生长流式输出的消息
- 观察 assistant / reasoning 文本持续增长时，是否只表现为局部文本自然追加
- 确认不再出现整卡闪烁、明显跳变、鬼畜双动画

Web：

- 在 sessions detail 中复现长流式输出
- 观察同类 assistant 消息是否仍会整块闪烁
- 流式结束切换到完整富渲染时是否平顺

### 3. 动画一致性验证

- 导出配置弹窗进场/退场
- 导出进度弹窗进场/退场
- 会话上下文菜单弹出/收起
- 流式完成后正文增强切换

确认它们继续遵守全局动画设置，而非出现生硬切换。

### 4. 构建与交付约束

- 按用户要求，在提交前执行 `scripts/build_web.sh`
- 再运行与本次变更直接相关的最小验证命令
- 若创建 commit，commit message 必须使用简体中文
- 不执行 `git push`

## 取舍说明

本设计刻意不追求“流式期间完整 markdown 交互 100% 实时可用”。因为当前主要用户痛点是体感闪烁与整卡刷新，而不是 streaming 过程中必须立刻点击每个链接/代码块。将富渲染延后到 settled 阶段，能换取更稳定、更自然的流式体验，是本次最符合目标的取舍。

## 结论

本次改动采用两条主线同时推进：

1. 统一导出文件名规范化，彻底修复 APP + Web + 服务端的 `.jsonl` 重复/错配问题。
2. 将 APP + Web 流式消息改造成“轻流式 + 完成后增强”，从根因上消除 streaming 期间整卡抖动、闪烁和硬刷新。

该方案范围聚焦、根因明确、跨端一致，并与现有全局动画体系保持兼容。