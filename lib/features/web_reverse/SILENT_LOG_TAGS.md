# web_reverse 诊断日志清单（silentLog tags）

`silentLog(tag, where, error, [stack])` 仅在 debug 树中保留，release 被 tree-shake。  
本表覆盖 web_reverse 子树所有面板，便于排错时按 tag 快速 grep。

> 约定：dialog 文件 → tag 与文件名 stem 一致（snake_case）。早期 `'web-reverse'` 通配 tag 已逐步收敛到具体面板，新增面板必须遵循约定。

## 2026-Q2 新增面板（本批）

| Tag | 文件 | 触发位 (where) | 含义 |
| --- | --- | --- | --- |
| `web_reverse_animations_dialog` | [web_reverse_animations_dialog.dart](web_reverse_animations_dialog.dart) | `setPlaybackRate` / `refresh` / `bulk.<method>` / `row.<method>` / `copy` | 全局动画速率、`document.getAnimations` 快照、批量/单条 play/pause/cancel、JSON 复制 |
| `web_reverse_rendering_dialog` | [web_reverse_rendering_dialog.dart](web_reverse_rendering_dialog.dart) | `send.<method>` | `Overlay.*`/`Emulation.set*` 调用失败（PaintRects / LayoutShift / FPSCounter / WebVitals / CPU throttle / media emulation） |
| `web_reverse_issues_dialog` | [web_reverse_issues_dialog.dart](web_reverse_issues_dialog.dart) | `copy` | `Audits.issueAdded` 单条 JSON 复制；监听器与 `Audits.enable` 失败由 controller `silentLog('web_reverse_session_controller', ...)` 兜底 |
| `web_reverse_vitals_dialog` | [web_reverse_vitals_dialog.dart](web_reverse_vitals_dialog.dart) | `bootstrap` / `pull` / `reset` / `copy` | PerformanceObserver 注入失败、1 Hz `JSON.stringify(window.__oh_vitals)` 拉取异常、重置/复制报告 |

## 已存在的稳定 tag（节选，供 grep 索引）

- `web_reverse_session_controller` — 会话生命周期、CDP 事件总线、DOM/Network/Storage 调用（最常被 attach）
- `web_reverse_cdp_client` — 底层 WebSocket / `_onMessage` 解码
- `web_reverse_dashboard_dialog` — Dashboard 入口、`exportSnapshot/importSnapshot`、性能 trace 写入
- `web_reverse_artifacts` — HAR/Console artifact 持久化
- `web_reverse_har_persistence` / `web_reverse_har_replay_server` — HAR 离线导入回放
- `web_reverse_websocket_dialog` (现为 `web-reverse` 中 `ws.*`) — WS 帧重放/复制；迁移时按下方旧通配 tag 清单逐面板收敛
- `web_reverse_coverage_dialog` / `web_reverse_css_coverage_dialog` — JS / CSS 覆盖率
- `web_reverse_jwt`, `web_reverse_ws_inject`, `web_reverse_pm`, `web_reverse_geo_override`, `web_reverse_webauthn`, `web_reverse_ai_crypto`, `web_reverse_callgraph`, `web_reverse_dom_mutation`, `web_reverse_account_snapshots_dialog`, `web_reverse_collection_export`, `web_reverse_mock_rules`, `web_reverse_waterfall_dialog`, `web_reverse_resend_request_dialog`, `web_reverse_headless_batch`, `web_reverse_mitmproxy_bridge`, `web_reverse_lsp_client`

## 仍待收敛的旧通配 tag `'web-reverse'`

历史快速面板使用了泛 tag，排错时需要靠 `where` 字段二次定位：

- `cors.*` → `web_reverse_cors_preflight_dialog.dart`
- `frame-tree.*` → `web_reverse_frame_tree_dialog.dart`
- `cdp-console.*` → `web_reverse_cdp_console_dialog.dart`
- `heap-snapshot.*` → `web_reverse_heap_snapshot_dialog.dart`
- `css-cov.*` → `web_reverse_css_coverage_dialog.dart`
- `sourcemap.*` → `web_reverse_sourcemap_dialog.dart`
- `input-sim.*` → `web_reverse_input_sim_dialog.dart`
- `device-emu.*` → `web_reverse_device_emulation_dialog.dart`
- `cpu-throttle.*` → `web_reverse_cpu_throttle_dialog.dart`
- `perf-trace.*` → `web_reverse_perf_trace_dialog.dart`
- `dom-search.*` → `web_reverse_dom_search_dialog.dart`
- `storage.*` → `web_reverse_storage_dialog.dart`
- `repl.*` → `web_reverse_repl_dialog.dart`
- `replay.*` → `web_reverse_replay_dialog.dart`
- `ws.*` → `web_reverse_websocket_dialog.dart`
- `console.cluster.*` → `web_reverse_console_cluster_dialog.dart`

后续 PR 可分批改为各自的 dialog tag（每次收敛单个面板的 5 行 sed），不必一次性铺开。

## 排错用法

```bash
# 抓取某面板最近一次异常（debug build 控制台）
grep '\[silentLog\]\[web_reverse_vitals_dialog\]' ~/Library/Logs/OpenHand/*.log

# 全量列出仓库使用过的 tag
grep -rhoE "silentLog\('[^']+'" lib/ | sort -u
```
