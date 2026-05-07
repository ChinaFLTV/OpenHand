import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'app/model/app_info.dart';
import 'app/openhand_app.dart';
import 'app/state/settings_controller.dart';
import 'app/support/app_runtime_context.dart';
import 'app/support/silent_log.dart';
import 'app/support/system_proxy.dart';
import 'features/ai/ai_session_controller.dart';
import 'features/ai/service/ai_chat_service.dart';
import 'features/ai/service/ai_claude_hook_service.dart';
import 'features/ai/service/ai_protocol_adapter.dart' as ai_protocol_adapter;
import 'features/ai/service/lsp_client_service.dart';
import 'features/ai/service/self_learning_dispatcher.dart';
import 'features/ai/service/self_learning_runner.dart';
import 'features/ai/service/self_learning_scheduler.dart';
import 'features/crons/cron_history_cleanup_worker.dart';
import 'features/crons/crons_controller.dart';
import 'features/hooks/hooks_controller.dart';
import 'features/hooks/hooks_executor.dart';
import 'features/instructions/instructions_controller.dart';
import 'features/mcp/mcp_controller.dart';
import 'features/mcp/service/mcp_tool_discovery_service.dart'
    show mcpStdioMirrorModeOverride;
import 'features/memory/memory_controller.dart';
import 'features/message_gateway/message_gateway_controller.dart';
import 'features/skills/skills_controller.dart';
import 'shared/data/database_service.dart';

Future<void> main() async {
  // Use a guarded zone so uncaught async errors (including stray
  // FormatExceptions from third-party markdown/highlight rendering) cannot
  // crash the engine or flood the console during message rendering.
  //
  // The `print` override is critical: the `highlight` package swallows
  // FormatExceptions inside its keyword compiler and emits them via bare
  // `print(err)` (see package:highlight/src/highlight.dart). Those lines
  // can't be intercepted by FlutterError.onError or the zone error handler,
  // only by intercepting `print` at the zone level. Left unchecked, each
  // `print` call synchronously writes to the platform log from the UI
  // isolate, which is a measurable contributor to first-paint jank when a
  // conversation contains many code blocks.
  await runZonedGuarded<Future<void>>(
    _bootstrap,
    _handleUncaughtZoneError,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (_shouldSilencePrintLine(line)) {
          return;
        }
        parent.print(zone, line);
      },
    ),
  );
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_shouldSilenceRenderingError(details.exception)) {
      if (kDebugMode) {
        debugPrint(
          '[openhand] swallowed rendering error: ${details.exceptionAsString()}',
        );
      }
      return;
    }
    if (details.exceptionAsString().contains(
      'is dispatched, but the state shows that the physical key is',
    )) {
      return;
    }
    if (originalOnError != null) {
      originalOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  // Absorb async errors reported through the platform dispatcher so a single
  // stray FormatException cannot cascade into repeated frame rebuilds.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_shouldSilenceRenderingError(error)) {
      if (kDebugMode) {
        debugPrint('[openhand] swallowed async error: $error');
      }
      return true;
    }
    return false;
  };

  // Initialize database before creating any controllers that depend on it.
  try {
    await DatabaseService.initialize();
  } catch (error, stackTrace) {
    debugPrint('Fatal: database initialization failed: $error\n$stackTrace');
    runApp(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF1B1B1B),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                '数据库初始化失败 / Database initialization failed\n'
                '\n'
                '原因 / Why:\n'
                '$error\n'
                '\n'
                '建议 / Try:\n'
                '· 检查 Application Support 目录是否可写 / 是否被其他实例占用\n'
                '· 检查磁盘剩余空间是否充足\n'
                '· 退出其他 OpenHand 进程后再启动 (sqlite 不允许同库多写)\n'
                '· 必要时备份并删除 openhand.db 让程序重新建库',
                style: const TextStyle(
                  color: Color(0xFFE0E0E0),
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  // Defer best-effort cleanup of stale temp artifacts until AFTER the first
  // frame is painted: although `unawaited`, both helpers issue filesystem
  // syscalls (Directory.list + stat + delete) on the same isolate event
  // loop that the 7 controller initializers are competing for, and they
  // are not on the critical path for showing the UI.
  final settingsControllerFuture = SettingsController.create();
  final appInfoFuture = _loadAppInfo();
  final hooksControllerFuture = HooksController.create();
  // 2026-05-03: kick off system-proxy detection in parallel with the
  // controllers — internal HTTP clients (WebSearch / WebFetch) consult
  // SystemProxyResolver lazily, so this is purely best-effort.
  final systemProxyFuture = SystemProxyResolver.instance.initialize();

  developer.Timeline.startSync('openhand.boot.await_settings_hooks');
  final settingsController = await settingsControllerFuture;
  final hooksController = await hooksControllerFuture;
  developer.Timeline.finishSync();
  // 2026-05-03 — settings 加载完成后立刻把代理偏好同步给 resolver；
  // 后续设置变更通过 listener 同步，全程不需要重启。
  SystemProxyResolver.instance.applyConfig(settingsController.proxySettings);
  settingsController.addListener(() {
    SystemProxyResolver.instance.applyConfig(settingsController.proxySettings);
  });
  // 2026-05-04 — stdio MCP 镜像源模式（auto / forceOn / forceOff）。
  // 用一个简单 top-level 变量同步给 mcp_tool_discovery_service，
  // 避免给已稳定的 service 强行喂 SettingsController 依赖。
  mcpStdioMirrorModeOverride = settingsController.mcpStdioMirrorMode;
  settingsController.addListener(() {
    mcpStdioMirrorModeOverride = settingsController.mcpStdioMirrorMode;
  });
  // 2026-04-25 Hermes Talker — expose a late-bound MemoryController handle to
  // AiSessionController so the Memory builtin tool (self-learning sub-agent)
  // can reach the real controller once it finishes loading.
  MemoryController? memoryControllerHandle;
  final aiSessionControllerFuture = AiSessionController.create(
    hookService: AiClaudeHookService(),
    userHooksExecutor: HooksExecutor(controller: hooksController),
    skillsDirProvider: () => settingsController.skillsStoragePath,
    memoryControllerProvider: () => memoryControllerHandle,
  );
  AiLspClientService.instance.updateLanguageSettings(
    settingsController.editorLspSettings,
  );
  settingsController.addListener(() {
    AiLspClientService.instance.updateLanguageSettings(
      settingsController.editorLspSettings,
    );
  });
  final skillsController = SkillsController.uninitialized(
    initialStoragePath: settingsController.skillsStoragePath,
  );
  unawaited(skillsController.refresh());
  final mcpController = McpController.uninitialized(
    initialFilePath: settingsController.mcpServersFilePath,
    autoProbeConcurrency: settingsController.mcpAutoProbeConcurrency,
  );
  unawaited(mcpController.refresh());
  // 2026-04-25 boot perf — MemoryController is only consumed inside
  // user-action code paths (`_buildRuntimeContext` + self-learning sub-agent
  // tools), never at first paint of the home shell. Construct it
  // synchronously and refresh in the background so its sqlite load no
  // longer sits on the boot critical path.
  final memoryController = MemoryController.uninitialized();
  unawaited(memoryController.refresh());
  // 2026-04-25 boot perf — CronsController only matters once the user opens
  // the Crons view OR a scheduled tick fires. Construct it synchronously so
  // we can register the Hermes Talker agent handler before runApp, then run
  // the sqlite load + scheduler startup in the background. The agent
  // handler is a plain field setter and does not require initialize() to
  // have completed.
  final cronsController = CronsController.uninitialized();
  // 2026-04-25 — InstructionsController: 与 memory 同样“非首屏关键路径”，
  // 同步构造 + 后台 refresh，确保启动期间不阻塞首帧。
  final instructionsController = InstructionsController.uninitialized();
  unawaited(instructionsController.refresh());
  final appInfo = await appInfoFuture;
  AppRuntimeContext.initialize(appInfo);
  developer.Timeline.startSync('openhand.boot.await_remaining_controllers');
  memoryControllerHandle = memoryController;
  final aiSessionController = await aiSessionControllerFuture;
  developer.Timeline.finishSync();
  // Make sure system-proxy detection has resolved before the user can
  // hit WebSearch/WebFetch. Best-effort — failures fall back to DIRECT.
  unawaited(systemProxyFuture);

  // 2026-04-25 Hermes Talker — bootstrap the self-learning scheduler + runner
  // and register the `agent` cron handler so the system-managed
  // `self_learning.hermes_talker` entry can fire every 5 minutes.
  //
  // The dispatcher runs a restricted sub-agent: it exposes ONLY the `Memory`
  // and `SkillManager` built-in tools to the model and drives a streaming
  // tool-call loop so the LLM can actually persist memory / profile / skill
  // changes (not just summarise them). Text + reasoning deltas are piped
  // into the self-learning card for live observability.
  final selfLearningChatClient = AiChatService();
  final selfLearningRunner = SelfLearningRunner(
    sessionController: aiSessionController,
    memoryController: memoryController,
    llmDispatcher: buildSelfLearningDispatcher(
      chatClient: selfLearningChatClient,
      settingsController: settingsController,
      memoryController: memoryController,
    ),
  );
  final selfLearningScheduler = SelfLearningScheduler(
    sessionStore: aiSessionController.store,
    settingsController: settingsController,
    runForSession: selfLearningRunner.runForSession,
    concurrency: settingsController.selfLearningConcurrency,
  );
  cronsController.registerAgentHandler((entry) async {
    if (entry.tags.contains(CronsController.hermesTalkerTag)) {
      final result = await selfLearningScheduler.tick();
      final stdout =
          'ok: scanned=${result.scanned} triggered=${result.triggered} '
          'skipped=${result.skipped} errors=${result.errors}';
      final appContext = <String, String>{};
      try {
        appContext[CronsController.hermesTalkerStatsKey] =
            jsonEncode(<String, int>{
              'scanned': result.scanned,
              'triggered': result.triggered,
              'skipped': result.skipped,
              'errors': result.errors,
            });
        // 仅在确实存在执行报告时附加 Hermes Talker 会话富数据；统计信息
        // 始终保存，便于历史记录展示无变更的巡检现场。
        if (result.reports.isNotEmpty) {
          appContext[CronsController.hermesTalkerReportsKey] = jsonEncode(
            result.reports.map((r) => r.toJson()).toList(),
          );
        }
      } catch (error, stack) {
        // JSON 编码失败时降级为纯 stdout，保留诊断线索但不影响调度链路。
        silentLog('main', 'encode hermes talker context', error, stack);
      }
      return AgentHandlerResult(stdout: stdout, appContext: appContext);
    }
    return AgentHandlerResult(
      stdout: 'noop: unknown agent tag (${entry.tags.join(",")})',
    );
  });
  settingsController.addListener(() {
    mcpController.updateAutoProbeConcurrency(
      settingsController.mcpAutoProbeConcurrency,
    );
    selfLearningScheduler.updateConcurrency(
      settingsController.selfLearningConcurrency,
    );
    SelfLearningRunner.streamFlushIntervalMs =
        settingsController.selfLearningStreamFlushIntervalMs;
  });
  // 启动期同步一次，避免首次 listener 触发前的 race。
  SelfLearningRunner.streamFlushIntervalMs =
      settingsController.selfLearningStreamFlushIntervalMs;
  // Kick off the deferred cron init AFTER the agent handler is registered so
  // any immediate scheduler tick post-init can dispatch correctly.
  unawaited(cronsController.initialize());

  final messageGatewayController = MessageGatewayController.uninitialized(
    sessionController: aiSessionController,
    settingsController: settingsController,
    skillsController: skillsController,
    mcpController: mcpController,
    memoryController: memoryController,
    cronsController: cronsController,
    instructionsController: instructionsController,
    appInfo: appInfo,
  );
  unawaited(messageGatewayController.initialize());

  // 2026-04-25 — 冷启动后异步触发一次 cron 历史清理（single-flight，
  // 永不抛异常，超时兜底 30s），不干扰主路径与 UI 启动。
  unawaited(
    runCronHistoryCleanupOnce(
      settings: settingsController,
      crons: cronsController,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
        ChangeNotifierProvider<SkillsController>.value(value: skillsController),
        ChangeNotifierProvider<McpController>.value(value: mcpController),
        ChangeNotifierProvider<HooksController>.value(value: hooksController),
        ChangeNotifierProvider<MemoryController>.value(value: memoryController),
        ChangeNotifierProvider<CronsController>.value(value: cronsController),
        ChangeNotifierProvider<InstructionsController>.value(
          value: instructionsController,
        ),
        ChangeNotifierProvider<MessageGatewayController>.value(
          value: messageGatewayController,
        ),
        ChangeNotifierProvider<AiSessionController>.value(
          value: aiSessionController,
        ),
        Provider<AppInfo>.value(value: appInfo),
      ],
      child: const OpenHandApp(),
    ),
  );
  developer.Timeline.instantSync('openhand.boot.runApp_called');

  // Best-effort cleanup of stale temp artifacts — deferred until after the
  // first frame is painted so it never competes with controller init or
  // first-paint work for the event loop.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(HooksExecutor.pruneStaleTempFiles());
    unawaited(ai_protocol_adapter.pruneInlineMediaCache());
  });
}

Future<AppInfo> _loadAppInfo() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    return AppInfo.fromPackageInfo(packageInfo);
  } catch (_) {
    return AppInfo.fallback();
  }
}

/// Returns `true` when an error looks like the benign kind we want to keep
/// out of the console. Primarily this targets [FormatException]s that leak
/// out of third-party markdown / syntax highlighting internals during
/// rendering — they are fully recoverable and we always fall back to plain
/// text, so presenting them as an error overlay only contributes to UI jank
/// on first paint of a long conversation.
bool _shouldSilenceRenderingError(Object error) {
  if (error is FormatException) {
    return true;
  }
  final message = error.toString();
  return message.contains('FormatException: Invalid number') ||
      message.contains('FormatException: Invalid radix-10 number');
}

/// Filter out the noisy, recoverable format-exception lines that the
/// `highlight` package emits via bare `print(err)` calls. These lines
/// originate inside keyword-table compilation and do not indicate a real
/// error — the highlight fallback still renders plain text correctly.
bool _shouldSilencePrintLine(String line) {
  return line.contains('FormatException: Invalid number') ||
      line.contains('FormatException: Invalid radix-10 number') ||
      line.contains('FormatException: Invalid radix-16 number');
}

void _handleUncaughtZoneError(Object error, StackTrace stack) {
  if (_shouldSilenceRenderingError(error)) {
    if (kDebugMode) {
      debugPrint('[openhand] swallowed zone error: $error');
    }
    return;
  }
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'openhand',
      context: ErrorDescription('uncaught zone error'),
    ),
  );
}
