<div align="center">
  <img src="assets/branding/openhand_logo.png" alt="OpenHand Logo" width="128" />

# OpenHand

[![Flutter](https://img.shields.io/badge/Flutter-%3E=3.27-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart SDK](https://img.shields.io/badge/Dart-%5E3.11-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-555)](#运行环境)
[![Status](https://img.shields.io/badge/status-active-brightgreen)](#)
[![中文](https://img.shields.io/badge/lang-简体中文-red)](README.md)
[![English](https://img.shields.io/badge/lang-English-blue)](README.en.md)

<p>
  <a href="README.md">简体中文</a>
  ·
  <a href="README.en.md">English</a>
</p>

</div>

OpenHand 是一款本地优先的跨平台桌面 AI 智能体工作台，面向开发者、研究人员和需要可控 AI 工作流的团队。它将多模型会话、工具调用、MCP、技能、记忆、钩子、定时任务和线程模板整合到一个 Flutter 原生应用中，用于构建可扩展、可审计、可长期维护的 AI 桌面工作环境。

## 项目介绍

OpenHand 的目标不是只做一个聊天窗口，而是提供一个可以承载真实任务的本地 AI 工作台。用户可以在同一个应用中完成模型配置、工程协作、文件操作、浏览器调试、MCP 服务管理、技能沉淀、长期记忆维护和自动化任务编排。

它适合以下场景：

- 日常 AI 对话、知识整理和长期记忆沉淀。
- 代码阅读、修改、调试、项目上下文分析和工程任务推进。
- Web 逆向、浏览器调试、接口分析和页面行为排查。
- MCP 服务、工具、技能、提示模板和本地配置的统一管理。
- 需要本地优先、权限可控、过程可追踪的 AI 辅助工作流。

## 主要功能

- 多模型接入：支持 OpenAI、Claude、Gemini、DeepSeek、Qwen、Kimi、GLM、Grok、Ollama、vLLM、SGLang、MiniMax 等多类接口。
- 智能体工具链：内置文件读写、编辑、搜索、Bash、Git、LSP、WebFetch、WebSearch、Todo、Memory、Skill Manager 等能力。
- 线程模板：提供普通会话、Programming Expert、Harness Engineering、Web Reverse Expert、Hermes Talker 等工作流入口。
- MCP 管理：集中管理 Model Context Protocol 服务、工具清单、启停状态和运行配置。
- 技能系统：管理本地技能、提示模板和可复用能力包，支持将经验沉淀为可复用资产。
- 记忆系统：维护可检索的用户资料、偏好、项目背景和长期知识。
- 自动任务：通过 Hooks 和 Crons 执行会话生命周期动作、后台维护任务和定时工作流。
- 桌面交互：支持多线程会话、附件、代码高亮、Markdown、KaTeX、快捷键、主题和多语言界面。

## 产品特性

- 本地优先：会话、记忆、技能、MCP 配置和设置默认保存在本机，便于掌控数据边界。
- 可扩展：模型协议、工具、MCP、技能、钩子和线程模板按模块组织，便于持续扩展。
- 可控执行：命令规则、沙箱配置、外部进程超时、取消和强制终止策略统一管理。
- 兼容降级：模型不支持原生 function calling 时，可通过 DSML 结构化文本协议驱动工具调用。
- 工程化体验：面向真实项目协作设计，提供文件浏览、上下文收集、任务规划、执行记录和结果验收能力。
- 原生桌面：基于 Flutter 构建，覆盖 macOS、Windows 和 Linux，兼顾性能、稳定性和一致体验。

## 应用截图

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/01-main-chat.png" alt="主聊天界面" /><br/><sub><b>主聊天</b></sub></td>
    <td align="center"><img src="docs/screenshots/02-programming-expert.png" alt="编程专家" /><br/><sub><b>编程专家</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/03-harness.png" alt="Harness Engineering" /><br/><sub><b>Harness Engineering</b></sub></td>
    <td align="center"><img src="docs/screenshots/04-mcp-servers.png" alt="MCP 服务" /><br/><sub><b>MCP 服务</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/05-skills-market.png" alt="技能市场" /><br/><sub><b>技能市场</b></sub></td>
    <td align="center"><img src="docs/screenshots/06-settings.png" alt="设置中心" /><br/><sub><b>设置中心</b></sub></td>
  </tr>
</table>

## 线程模板

OpenHand 提供可复用的线程模板，用于快速切换不同工作流。

- Programming Expert：面向代码阅读、修改、调试和项目协作，包含项目文件浏览器和开发上下文。
- Harness Engineering：阶段化工程流水线，覆盖元数据采集、调查、规划、实施和验收，可使用 CLI 或 URL/API 模型执行角色任务。
- Web Reverse Expert：面向 Web 逆向与浏览器调试，整合 CDP、网络、控制台、源码、Hook、存储和性能分析。
- Hermes Talker：面向长期陪伴式对话和记忆沉淀。

## 工具与扩展

- MCP：管理 Model Context Protocol 服务和工具目录。
- Skills：管理本地技能、提示模板和可复用能力包。
- Hooks：在会话生命周期中执行可配置脚本或动作。
- Crons：管理定时任务和后台维护任务。
- Memory：维护可检索的用户资料、偏好和长期知识。

## 运行环境

- Flutter 3.27 或更高版本
- Dart 3.11 或更高版本
- macOS、Windows 或 Linux 桌面环境
- 可选：目标模型服务的 API Key、本地模型服务、外部 CLI 工具

## 本地开发

```bash
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
flutter run -d macos
```

按平台构建：

```bash
flutter build macos
flutter build windows
flutter build linux
```

项目提供 Web 资源重建脚本：

```bash
scripts/build_web.sh
```

## 项目结构

```text
lib/
  app/                 应用设置、主题、路径和通用状态
  features/
    ai/                会话、模型协议、工具运行时和提示词构建
    home/              主界面、线程列表、编辑器和模板入口
    hardness/          Harness Engineering 流水线
    web_reverse/       Web 逆向与浏览器调试能力
    skills/            技能管理
    memory/            记忆系统
    mcp/               MCP 服务管理
    hooks/             生命周期钩子
    crons/             定时任务
  l10n/                国际化资源
assets/
  prompts/             内置提示词
  branding/            品牌资源
scripts/               构建与维护脚本
test/                  单元与组件测试
```

## 数据与配置

OpenHand 默认使用本地应用目录保存运行数据。具体路径可在设置页查看，包括：

- 应用设置
- AI 模型配置
- 会话数据
- MCP 服务配置
- 技能目录
- 记忆文件

敏感信息应通过本机安全存储或受控配置管理，不建议提交到版本库。

## 开发约定

- Prompt 内容保持简洁、明确、结构化，避免冗余和互相矛盾的指令。
- UI 变更遵循现有动画、弹窗和主题规范。
- 涉及外部进程、网络请求、文件系统和循环任务时，必须设置清晰的超时、取消和资源释放路径。
- 提交前运行格式化、静态分析、测试和必要构建脚本。

## 许可证

本项目许可证以仓库中的 LICENSE 文件为准。
