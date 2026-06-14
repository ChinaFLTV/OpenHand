<div align="center">
  <img src="assets/branding/openhand_logo.png" alt="OpenHand Logo" width="128" />

# OpenHand

[![Flutter](https://img.shields.io/badge/Flutter-%3E=3.27-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart SDK](https://img.shields.io/badge/Dart-%5E3.11-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-555)](#requirements)
[![Status](https://img.shields.io/badge/status-active-brightgreen)](#)
[![中文](https://img.shields.io/badge/lang-简体中文-red)](README.md)
[![English](https://img.shields.io/badge/lang-English-blue)](README.en.md)

<p>
  <a href="README.md">简体中文</a>
  ·
  <a href="README.en.md">English</a>
</p>

</div>

OpenHand is a local-first, cross-platform desktop workbench for AI agents, built for developers, researchers, and teams that need controllable AI workflows. It brings multi-model chats, tool execution, MCP, skills, memory, hooks, scheduled jobs, and thread templates into one native Flutter app for extensible, auditable, and maintainable desktop AI work.

## Introduction

OpenHand is designed to be more than a chat window. It provides a local AI workbench where users can manage models, engineering workflows, file operations, browser debugging, MCP servers, reusable skills, long-term memory, and automation in one application.

It is useful for:

- Daily AI conversations, knowledge organization, and long-term memory.
- Code reading, editing, debugging, project context analysis, and engineering execution.
- Web reverse engineering, browser debugging, API analysis, and page behavior inspection.
- Unified management of MCP servers, tools, skills, prompt templates, and local settings.
- AI-assisted workflows that need local-first storage, explicit permissions, and traceable execution.

## Main Features

- Multi-model access: OpenAI, Claude, Gemini, DeepSeek, Qwen, Kimi, GLM, Grok, Ollama, vLLM, SGLang, MiniMax, and more.
- Agent toolchain: file read/write/edit/search, Bash, Git, LSP, WebFetch, WebSearch, Todo, Memory, Skill Manager, and related capabilities.
- Thread templates: regular chat, Programming Expert, Harness Engineering, Web Reverse Expert, Hermes Talker, and other workflow entry points.
- MCP management: centralized management for Model Context Protocol servers, tool catalogs, runtime status, and configuration.
- Skill system: manage local skills, prompt templates, and reusable capability packages.
- Memory system: maintain retrievable user profiles, preferences, project background, and long-term knowledge.
- Automation: use Hooks and Crons for session lifecycle actions, background maintenance, and scheduled workflows.
- Desktop interaction: multi-thread sessions, attachments, syntax highlighting, Markdown, KaTeX, shortcuts, themes, and localization.

## Product Traits

- Local-first: sessions, memories, skills, MCP configuration, and settings are stored locally by default.
- Extensible: model protocols, tools, MCP, skills, hooks, and thread templates are organized as maintainable modules.
- Controlled execution: command rules, sandbox settings, process timeouts, cancellation, and forced termination are managed consistently.
- Compatible fallback: models without native function calling can still drive tools through the DSML structured text protocol.
- Engineering-focused: project workflows include file browsing, context collection, task planning, execution records, and review.
- Native desktop: built with Flutter for macOS, Windows, and Linux with consistent performance and interaction.

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

OpenHand includes reusable thread templates for common workflows.

- Programming Expert: code reading, editing, debugging, and project collaboration with a project file explorer.
- Harness Engineering: phased engineering workflow for metadata collection, reading, planning, implementation, and review, using CLI or URL/API model roles.
- Web Reverse Expert: browser-driven reverse engineering with CDP, network, console, source, hook, storage, and performance panels.
- Hermes Talker: long-running conversational assistance with memory distillation.

## Tools And Extensions

- MCP: manage Model Context Protocol servers and tool catalogs.
- Skills: manage local skills, prompt templates, and reusable capability packages.
- Hooks: run configurable scripts or actions during session lifecycle events.
- Crons: manage scheduled jobs and background maintenance tasks.
- Memory: maintain retrievable user profile data, preferences, and long-term knowledge.

## Requirements

- Flutter 3.27 or later
- Dart 3.11 or later
- macOS, Windows, or Linux desktop environment
- Optional: API keys, local model services, or external CLI tools for target providers

## Local Development

```bash
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
flutter run -d macos
```

Build per platform:

```bash
flutter build macos
flutter build windows
flutter build linux
```

Rebuild bundled Web resources:

```bash
scripts/build_web.sh
```

## Project Layout

```text
lib/
  app/                 app settings, theme, paths, and shared state
  features/
    ai/                sessions, model protocols, tool runtime, prompts
    home/              main UI, thread list, editor, and template entrypoints
    hardness/          Harness Engineering pipeline
    web_reverse/       Web reverse engineering and browser debugging
    skills/            skill management
    memory/            memory system
    mcp/               MCP server management
    hooks/             lifecycle hooks
    crons/             scheduled jobs
  l10n/                localization resources
assets/
  prompts/             bundled prompts
  branding/            brand assets
scripts/               build and maintenance scripts
test/                  unit and widget tests
```

## Data And Configuration

OpenHand stores runtime data in local application directories by default. Paths are visible in Settings, including:

- app settings
- AI model configuration
- session data
- MCP server configuration
- skills directory
- memory files

Sensitive values should be stored through local secure storage or controlled configuration management, not committed to the repository.

## Development Notes

- Keep prompt content concise, direct, structured, and free of conflicting instructions.
- Follow existing animation, dialog, and theme conventions for UI changes.
- External processes, network requests, filesystem operations, and scheduled loops must have clear timeout, cancellation, and cleanup paths.
- Run formatting, static analysis, tests, and required build scripts before committing.

## License

See the LICENSE file in this repository.
