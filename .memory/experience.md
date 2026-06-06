# 经验教训

## 异步

- **[坑点]** Web 端 SSE 正常存活时，低频 phase guard polling 仍回写 running 阶段的消息窗口；这些轮询结果可能落后于 SSE 实时窗口，短暂把助手/思考 tail 回退到历史工具卡，导致自动跟随目标跳错、消息卡显隐和滚动抖动。
  **[解决/规避]** 在 `clients/web/src/features/sessions/components/SessionDetailPage.tsx` 中让 `shouldApplyPollingMessageWindow(sseLive, pollSendPhase)` 跳过 `sseLive && running` 的消息窗口，只允许 SSE 失效时或 polling 返回 `idle` 结束帧时应用；自动跟随 tail 与渲染共用 `messagesInDisplayOrder`，避免未排序窗口再次选错尾部。

## 平台兼容

- **[坑点]** macOS 上 `webview_flutter` 把 WKWebView 作为 Flutter 子图层渲染，Flutter 的命中测试会先消费掉 pointer 事件而不再向下转发到 WebView；iOS / Android 上的 WebView 走原生层能正常收到 pointerdown / wheel / pinch，导致 macOS 端任何依赖 WebView 内部手势（pan/zoom、canvas 拖拽）的实现"看起来不响应"。
  **[解决/规避]** 在 macOS 分支用 `Listener(behavior: HitTestBehavior.translucent)` 包裹 `WebViewWidget`，把 `onPointerDown/Move/Up/Cancel`、`PointerScrollEvent`、`PointerPanZoomStart/Update/End` 都桥接到 WebView 内的 JS：普通 pointer 走 `stage.dispatchEvent(new PointerEvent(...))`，滚轮缩放与 trackpad pinch 走 `__openhandZoomAt(factor, anchorX, anchorY)`，trackpad 双指 pan 走 `__openhandPan(dx, dy)`；非 macOS 平台直接返回裸 `WebViewWidget`，不要无脑包 Listener，避免遮挡原生手势。

## UI

- **[坑点]** Flutter `Column` 默认 `crossAxisAlignment: CrossAxisAlignment.start` 时，子节点拿到的是松约束，宽度按 intrinsic 计算；`Stack(Positioned.fill)` 嵌在 `Column` 内部时也只继承 intrinsic 宽，最终 WebView viewport 与内部 canvas 渲染成 `0×0`，所有命中测试与 `getBoundingClientRect()` 都失效。
  **[解决/规避]** 在外层 Column 派发到"宽度需要撑满父容器"的子组件（`WebViewWidget`、图表、`Stack`）时，套一个 `SizedBox(width: double.infinity)` 强制拉伸；或把外层 Column 改成 `CrossAxisAlignment.stretch`；纯 `Stack(Positioned.fill)` 自身不会按父宽布局，必须有外层 SizedBox / ConstrainedBox 给到确定宽度。

## 交互

- **[坑点]** WebView 内实现"按画布拖动 + 节点点击转发"时，若在 `pointerdown` 一开始就标记 `dragReady = true` 并清空 `tapStart`，后续 `wasTap`（`tapStart != null && !pointerMoved && !dragReady`）永远为 false，导致鼠标单击、键盘可达性、节点 link 全部失活；macOS trackpad 单指点击尤为明显。
  **[解决/规避]** canvas 拖拽手势改为"长按后再进入拖动"：保留 `tapStart` 与 `pointerMoved` 判定 `wasTap`；只有 `pointerdown` 持续超过长按阈值（如 220ms）且位移未超阈值时，才把状态切到 `dragging` 并吞掉 `click`；移动端用触屏长按，桌面端用更短阈值但仍要保留单击窗口。
