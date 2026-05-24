# 经验教训

## 异步

- **[坑点]** Web 端 SSE 正常存活时，低频 phase guard polling 仍回写 running 阶段的消息窗口；这些轮询结果可能落后于 SSE 实时窗口，短暂把助手/思考 tail 回退到历史工具卡，导致自动跟随目标跳错、消息卡显隐和滚动抖动。
  **[解决/规避]** 在 `clients/web/src/features/sessions/components/SessionDetailPage.tsx` 中让 `shouldApplyPollingMessageWindow(sseLive, pollSendPhase)` 跳过 `sseLive && running` 的消息窗口，只允许 SSE 失效时或 polling 返回 `idle` 结束帧时应用；自动跟随 tail 与渲染共用 `messagesInDisplayOrder`，避免未排序窗口再次选错尾部。
