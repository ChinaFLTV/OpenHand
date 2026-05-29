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
- `message_path_linking.dart` 全部公开：`MessageResolvedPath / MessagePathCodeSyntax / MessageFilePathSyntax / resolveMarkdownMessageLinkPath / resolveExistingMessagePath / resolveExistingMessagePathAsync / parseSupportedMessageLinkUri / messageFilePathRoots`（供 hardness session_dashboard 使用）

## 目录组织

```
lib/features/home/
  openhand_home_page.dart        # 7294 行主页面（含 20 个 part 引用 widgets/_home_*.dart）
  index.dart
  README.md
  widgets/                       # 21 子文件：20 个 _home_*.part.dart + machine_expert_dialog
    _home_navigation.dart        # part of '../openhand_home_page.dart'
    _home_transcript.dart        # 同上
    _home_composer.dart          # 同上（3.7k 行）
    _home_message_bubble.dart    # 同上（3.8k 行）
    _home_tool_call_widgets.dart # 同上（3.9k 行）
    _home_file_mutation_widgets.dart  # 同上（4.1k 行）
    _home_programming_expert_file_explorer.dart  # 同上（14.4k 行，文件浏览器）
    ... 13 其他 _home_*.dart
    machine_expert_dialog.dart   # 819 行独立 dialog
  util/                          # 4 个工具：
    editor_indentation.dart      # 编辑器缩进推断
    slash_command_parser.dart    # /command 解析
    tool_call_argument_parser.dart # 工具调用参数解析
    message_path_linking.dart    # 消息内文件路径链接（含 markdown 语法）
  model / data / service / state # 占位（home 当前无自有 model/service）
```

## 不变量
- `widgets/_home_*.dart` 通过 `part of '../openhand_home_page.dart';` 与主页面共享 library 作用域；必须保持同 library 引用关系
- `openhand_home_page.dart` 至关重要：是 home 唯一 library 入口，所有 part 文件不能独立编译
- machine_expert_dialog 不是 part 文件；是独立 widget

## 跨 feature 依赖
- 入向：openhand_app.dart 通过 `import '../features/home/openhand_home_page.dart'` 注入到 MaterialApp.home
- 出向（通过 sibling barrel）：ai / mcp / hardness / settings / crons / hooks / instructions / memory / skills / plugin_service / message_gateway

## 拆分历史
- P2 完成：22 widget 部件归 widgets/，4 工具归 util/，model/data/service/state 占位
- 未拆：openhand_home_page.dart 7294 行（含整个 _OpenHandHomePageState）— 行数大但是 part files 已承担 90% 实现，主文件主要是 state 字段与 build() 流水线
