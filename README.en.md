# OpenHand

OpenHand is a local-first, cross-platform desktop workbench for AI agents. It brings model protocols, tool execution, MCP, skills, hooks, scheduled jobs, memory, and thread templates into one native Flutter app for developers and teams that need controllable, extensible, and auditable AI workflows.

[简体中文](README.md)

## Core Capabilities

- Model protocols: OpenAI, Claude, Gemini, DeepSeek, Qwen, Kimi, GLM, Grok, Ollama, vLLM, SGLang, MiniMax, and more.
- Agent toolchain: file read/write/edit/search, Bash, Git, LSP, WebFetch, WebSearch, Todo, Memory, Skill Manager, and related tools.
- DSML fallback: models without native function calling can still drive tools through a structured text protocol.
- Local data: sessions, memories, skills, MCP configuration, and settings are stored on the local machine by default.
- Safe execution: command rules, sandbox settings, process timeouts, and forced termination are managed consistently.
- Desktop experience: multi-thread sessions, attachments, syntax highlighting, Markdown, KaTeX, shortcuts, themes, and localization.

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
