# Home feature

OpenHand 桌面端主入口页（默认进入屏），承载会话面板、侧栏、composer、transcript、对话框等所有交互。

## 形态
widget-bundle。无自身全局 Controller — 状态分布在：
- 全局 `SettingsController`（`lib/app/state/`）
- `AiSessionController`、`McpController` 等 sibling feature 的 controller
- `_HomeXxxState` part-of 内部 setState

不在 main.dart 全局 providers 上挂自有 controller。

## 对外 API（barrel）
入口：`features/home/index.dart`。

- `OpenHandHomePage` — 主页面 widget
- `OpenHandSessionTokenUsageDial` 与缓存命中趋势（`session_cache_hit_trend` /
  `token_popup_cache_hit_trend_chart`）
- `message_path_linking.dart` 全部公开：`MessageResolvedPath / MessagePathCodeSyntax / MessageFilePathSyntax / resolveMarkdownMessageLinkPath / resolveExistingMessagePath / resolveExistingMessagePathAsync / parseSupportedMessageLinkUri / messageFilePathRoots`（供 harness session_dashboard 使用）

## 目录组织

```
lib/features/home/
  openhand_home_page.dart        # 主页面 library（含多个 widgets/_home_*.dart part）
  index.dart
  README.md
  widgets/                       # 页面 part、独立 dialog 与局部组件
    _home_navigation.dart        # part of '../openhand_home_page.dart'
    _home_transcript.dart        # 同上
    _home_composer.dart          # 同上
    _home_message_bubble.dart    # 同上
    _home_tool_call_widgets.dart # 同上
    _home_file_mutation_widgets.dart  # 同上
    _home_programming_expert_file_explorer.dart  # 同上（文件浏览器）
    ... 15 个其他 _home_*.dart part 文件，另有独立非 part 文件
    token_popup_cache_hit_trend_chart.dart 与 html_selection_bridge_clipboard.dart
  util/                          # 页面工具
    editor_indentation.dart      # 编辑器缩进推断
    slash_command_parser.dart    # /command 解析
    tool_call_argument_parser.dart # 工具调用参数解析
    message_path_linking.dart    # 消息内文件路径链接（含 markdown 语法）
  model/                         # home 自有轻量模型
```

## 不变量
- `widgets/_home_*.dart` 通过 `part of '../openhand_home_page.dart';` 与主页面共享 library 作用域；必须保持同 library 引用关系
- `openhand_home_page.dart` 至关重要：是 home 唯一 library 入口，所有 part 文件不能独立编译
- 机器专家模板直接创建会话，左侧工作区显示内建终端面板；不再使用独立配置弹窗。

## 跨 feature 依赖
- 入向：openhand_app.dart 通过 `import '../features/home/openhand_home_page.dart'` 注入到 MaterialApp.home
- 出向（通过 sibling barrel）：ai / android_reverse / crons / harness /
  hooks / instructions / knowledge_base / machine_terminal / mcp / memory /
  message_gateway / plugin_service / settings / skills /
  thread_template_runtime / web_reverse

## 拆分边界
- 页面部件归 `widgets/`，工具归 `util/`，轻量模型归 `model/`。
- `openhand_home_page.dart` 仍是 home 的唯一 library 入口；主 state 字段与 build 流水线保留在该文件，细节由 part 文件承载。
