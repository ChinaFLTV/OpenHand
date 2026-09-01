<div align="center">
  <img src="assets/branding/openhand_logo.png" alt="OpenHand Logo" width="128" />

# OpenHand

[![Flutter](https://img.shields.io/badge/Flutter-SDK-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart SDK](https://img.shields.io/badge/Dart-%5E3.12-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows-555)](#requirements)
[![Web Gateway](https://img.shields.io/badge/Web%20Gateway-Vite%20%2B%20Preact-646CFF)](#web-message-platform)
[![Status](https://img.shields.io/badge/status-active-brightgreen)](#)
[![中文](https://img.shields.io/badge/lang-简体中文-red)](README.md)
[![English](https://img.shields.io/badge/lang-English-blue)](README.en.md)

<p>
  <a href="README.md">简体中文</a>
  ·
  <a href="README.en.md">English</a>
</p>

</div>

OpenHand is a local-first AI workbench. It combines multi-model chat, tool execution, MCP, skills, memory, knowledge base, plugins, hooks, scheduled jobs, thread templates, and a Web message platform in one native Flutter app for real, controllable, auditable, and maintainable AI workflows.

## Positioning

OpenHand is more than a chat window. It is a local AI operations console for developers, researchers, and teams. It is useful for:

- Daily AI conversations, knowledge organization, user profiles, and long-term memory.
- Code reading, editing, debugging, project context analysis, and end-to-end engineering work.
- Multi-role engineering orchestration, task audit, execution records, and review.
- Unified management for MCP servers, plugins, skills, prompts, command rules, and local settings.
- Authorized Web / Android reverse engineering, security research, API analysis, and reproduction scripts.
- Browser access to sessions, files, plugins, logs, ops, and toolbox panels through the Web message platform.

## Core Capabilities

| Capability | Details |
|---|---|
| Multi-model access | Supports OpenAI, Claude, Gemini, DeepSeek, Qwen, Kimi, GLM, Grok, Ollama, vLLM, SGLang, MiniMax, Seed, StepFun, Wenxin, Hunyuan, Meta, Mimo, and OpenAI-compatible services. |
| Tool runtime | Built-in tools for file read/write/edit, diff application, Bash / background commands, Git, LSP, WebFetch, WebSearch, ToolSearch, Todo, Task, Memory, Knowledge, Skill Manager, and machine terminal workflows. |
| Controlled execution | Command allow / deny rules, write-command confirmation, sandbox settings, timeouts, cancellation, forced termination, tool-output compression, audit metadata, and token / cost statistics. |
| MCP and ToolSearch | MCP server management, stdio processes, health checks, tool discovery, keyword indexes, lazy loading, history import/export, and cancelled replay recovery. |
| Skills and plugins | Local Claude Code skills, skills marketplace, plugin scanning, installation, update, uninstall, dependency management, and runtime status. |
| Memory and self-learning | User profile, long-term memory, and Hermes Talker self-learning jobs for continuous personalization without noisy replies. |
| Knowledge base | Import Markdown, Office, PDF, HTML, CSV, JSON, TOML, YAML, TXT, code files, or notes; build a local Qdrant vector index and inspect retrieval details. |
| Automation | Hooks for session lifecycle events, Crons for scheduled jobs, background maintenance, system-managed jobs, and execution history. |
| Advanced workbenches | Web reverse CDP Dashboard, Android reverse Dashboard, Harness Engineering, and local machine terminal. |
| Desktop experience | Multi-thread sessions, attachments, Markdown / KaTeX / HTML rendering, syntax highlighting, shortcuts, themes, motion settings, localization, and smooth dialog/page transitions. |

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/01-main-chat.png" alt="Main chat" /><br/><sub><b>Main Chat</b></sub></td>
    <td align="center"><img src="docs/screenshots/02-programming-expert.png" alt="Programming Expert" /><br/><sub><b>Programming Expert</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/03-harness.png" alt="Harness Engineering" /><br/><sub><b>Harness Engineering</b></sub></td>
    <td align="center"><img src="docs/screenshots/04-mcp-servers.png" alt="MCP servers" /><br/><sub><b>MCP Servers</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/05-skills-market.png" alt="Skills market" /><br/><sub><b>Skills Market</b></sub></td>
    <td align="center"><img src="docs/screenshots/06-settings.png" alt="Settings" /><br/><sub><b>Settings</b></sub></td>
  </tr>
</table>

## Thread Templates

| Template | Purpose |
|---|---|
| Default Assistant | Claude Code style general-purpose template for tool-assisted work, MCP usage, and local skill activation. |
| Machine Expert | Uses the local terminal as the main execution surface for machine operations, troubleshooting, and automation. |
| Programming Expert | Code reading, editing, debugging, context recovery, subagent isolation, adversarial validation, and delivery. |
| Harness Engineering | Multi-role engineering orchestration with investigation, planning, implementation, review, and persistent context. |
| Hermes Talker | Adds skill_manager, memory, and self-learning to the default assistant for long-running personal conversations. |
| Web Reverse Expert | Uses Chrome / Chromium + CDP for authorized API reversing, parameters, storage, network, and reproduction scripts. |
| Android Reverse Expert | Uses ADB, Frida, jadx / apktool, and mitmproxy for authorized Android analysis. |
| Siri Assistant | Apple-focused template that inherits default capabilities and uses Siri-style system instructions; shown only on Apple platforms. |

## Workbench Modules

- `Workspace`: main chat, sidebar, composer, transcript, attachments, tool-call cards, file mutation previews, and slash commands.
- `MCP`: server configuration, connection state, tool discovery, lazy loading, ToolSearch history, and stdio ops.
- `Skills`: local skill scanning, install/uninstall, marketplace entry, and default prompt preview.
- `Memory`: user profile, long-term memory, CRUD, and runtime context injection.
- `Knowledge Base`: document parsing, chunking, embedding, Qdrant vector retrieval, retrieval details, and vector distribution.
- `Plugin Service`: plugin lifecycle, dependencies, Qdrant, Android toolchains, and other plugin capabilities.
- `Message Gateway`: Web access, auth, model allowlists, command approval, file-write approval, and log export.
- `Hooks / Crons / Instructions`: lifecycle scripts, scheduled jobs, user instructions, and project instructions.
- `Settings`: models, built-in tools, command rules, sandbox, proxy, animations, shortcuts, editor, cleanup, and system preferences.

## Web Message Platform

`clients/web` is OpenHand's browser console, built with Vite + Preact + TypeScript + Tailwind. Its build output is written to `assets/web` and served by the desktop Message Gateway.

The Web client includes:

- Session list, session detail, streaming messages, Markdown / KaTeX / Mermaid / syntax highlighting.
- Files, Harness, plugins, logs, ops, toolbox, and settings pages.
- Browser-side views for Web / Android reverse dashboards.
- Theme, language, dialog motion, PWA service worker, and hidden-page notification sync.
- Optional auth, access scopes, command approval, and file-write approval.

## Requirements

- Flutter `>=3.44.0` with Dart `^3.12.0`.
- Desktop targets: macOS and Windows. The repository currently does not include a Linux project directory, so this README does not claim Linux builds.
- Web asset builds: Node.js, npm / corepack, and `pnpm@11.7.0`. `scripts/build_web.sh` reuses local pnpm first, then falls back to corepack or `npm exec`.
- Optional dependencies: model API keys, local model services, Chrome / Chromium, Docker + Qdrant, ADB, Frida, jadx, apktool, mitmproxy, and external CLI tools.

## Local Development

```bash
flutter pub get
flutter gen-l10n
flutter analyze
flutter run -d macos
```

For Windows debugging:

```bash
flutter run -d windows
```

Build desktop targets:

```bash
flutter build macos
flutter build windows
```

Rebuild the bundled Web console:

```bash
scripts/build_web.sh
```

The script installs Web dependencies, clears old output, runs the Vite build, verifies `assets/web/{index.html,app.js,app.css}`, and runs `scripts/check_imports.dart` to enforce cross-feature imports and the shared animated-dialog entry point.

Web-only development:

```bash
cd clients/web
pnpm install
pnpm dev
```

## Project Layout

```text
lib/
  app/                       app state, settings, theme, paths, proxy, notifications, updates, runtime support
  shared/                    database, networking, shared UI, motion, utilities, concurrency, cleanup helpers
  features/
    ai/                      session state machine, model protocols, tool runtime, prompts, WebFetch/WebSearch
    home/                    main workbench, threads, composer, message rendering, file explorer, template entrypoints
    knowledge_base/          document import, parsing, chunking, embeddings, Qdrant retrieval and ops
    message_gateway/         Web platform service, auth, approvals, logs, runtime bridge
    plugin_service/          plugin scanning, install, update, uninstall, dependency management
    mcp/                     MCP servers, tool discovery, ToolSearch, stdio processes and ops
    skills/                  local skills, marketplace, install and uninstall
    memory/                  user profile and long-term memory
    instructions/            global and project user instructions
    hooks/                   lifecycle hooks
    crons/                   scheduled and system-managed jobs
    harness/                 Harness Engineering orchestration
    settings/                Settings pages for models, built-in tools, command rules, sandbox, proxy, animations, shortcuts and data cleanup
    web_reverse/             Web reverse CDP Dashboard and browser debugging
    android_reverse/         Android reverse Dashboard, ADB / Frida / network toolchain
    machine_terminal/        built-in terminal for Machine Expert
    thread_template_runtime/  thread-template runtime dependency linkage
  l10n/                      generated localization files
assets/
  prompts/                   bundled prompts, shared prompt sections, template-specific prompts
  branding/                  brand assets
  web/                       Web message platform build output
clients/web/                 Vite + Preact Web console source
docs/screenshots/            README screenshots
scripts/                     build, check, and maintenance scripts
```

## Data And Configuration

OpenHand stores runtime data under `~/.openhand` by default. Common paths include:

- `~/.openhand/openhand.db`: main SQLite database.
- `~/.openhand/sessions`: sessions, attachments, tool results, and compact-memory sidecars.
- `~/.openhand/mcp/mcp_servers.json`: MCP server configuration.
- `~/.openhand/skills`: local skills.
- `~/.openhand/memory/user-memory.json`: user memory file.
- `~/.openhand/message_gateway`: Web message platform configuration and runtime data.
- `~/.openhand/cache`, `~/.openhand/cache/media`, `~/.openhand/logs`: cache, media cache, and logs.

Sensitive values should live in local secure storage, environment variables, or controlled configuration, not in the repository.

## Development Notes

- Keep prompts concise, clear, structured, and free of conflicting or context-wasting instructions.
- UI changes should reuse motion, dialog, menu, button, scroll, and feedback components from `shared/ui`; dialog enter/exit motion must follow global motion settings.
- External processes, network requests, filesystem work, scheduled jobs, and retry loops must have timeout, cancellation, cleanup, and error fallback paths.
- Cross-feature dependencies should go through feature barrels; `scripts/build_web.sh` runs the import boundary check.
- Before committing, run the relevant formatting, analysis, tests, and `scripts/build_web.sh` when Web assets or the commit flow require it.

## License

This repository currently does not include a `LICENSE` file. Add an explicit license before open-source release, redistribution, or commercial use.
