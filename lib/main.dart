import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'app/model/app_info.dart';
import 'app/openhand_app.dart';
import 'app/state/settings_controller.dart';
import 'app/support/app_runtime_context.dart';
import 'app/support/input_repair_service.dart';
import 'app/support/safe_subprocess.dart';
import 'app/support/silent_log.dart';
import 'app/support/system_proxy.dart';
import 'features/ai/index.dart';
import 'features/ai/service/chat/ai_protocol_adapter.dart'
    as ai_protocol_adapter;
import 'features/crons/index.dart';
import 'features/hooks/index.dart';
import 'features/instructions/index.dart';
import 'features/mcp/index.dart';
import 'features/memory/index.dart';
import 'features/message_gateway/index.dart';
import 'features/plugin_service/index.dart';
import 'features/settings/service/throttle_auto_sync_service.dart';
import 'features/skills/index.dart';
import 'shared/db/database_service.dart';
import 'shared/fps/openhand_fps_monitor.dart';
import 'shared/ui/structured_error_text.dart';

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
  iaw.PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  // 2026-05-18 — 在 binding 初始化之后立刻启动 FPS 监视器，节流自动
  // 模式与 UI 卡顿降级会读它的 recentFps 数值。
  OpenHandFpsMonitor.instance.start();

  // 2026-05-19 —— IMK 全局输入死锁防御网：应用主进程被 SIGINT / SIGTERM
  // 杀掉时，先把所有登记在册的 osascript / LSP / mitmdump / npm 子进程
  // 一并 SIGTERM→SIGKILL，避免 macOS 上残留的 osascript 子进程继续向
  // 其他 GUI 应用投递 Apple Events、把 IMK 上下文留在 stale 状态，导致
  // 下次重启应用后全局 TextField 拒绝输入 / 复制 / 粘贴。配套
  // `AppLifecycleListener.onExitRequested`（在 OpenHandApp 内）覆盖
  // 正常退出路径；这里只接管异常 / 强杀路径。
  if (!Platform.isWindows) {
    for (final sig in <ProcessSignal>[
      ProcessSignal.sigint,
      ProcessSignal.sigterm,
    ]) {
      try {
        sig.watch().listen((_) async {
          try {
            await killAllTrackedChildren();
          } catch (error, stack) {
            silentLog('main', 'kill tracked children on signal', error, stack);
          }
          exit(0);
        });
      } catch (error, stack) {
        // 某些 sandbox / test 环境不允许装信号 handler，忽略。
        silentLog('main', 'install signal handler', error, stack);
      }
    }
  }

  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_shouldSilenceRenderingError(details.exception)) {
      debugLog(
        'openhand',
        'swallowed rendering error: ${details.exceptionAsString()}',
      );
      return;
    }
    // 2026-06-02 — 平台 IME 选区越界断言：framework 在
    // `TextInputClient.updateEditingState` 解析出
    // `Range start N is out of text of length M` 时，捕获后既会
    // `FlutterError.reportError` 又会 rethrow。此处吞掉红屏并触发
    // composer 轻量级 IME 软恢复（unfocus + requestFocus），把脱钩的
    // selection / composing 状态与 controller 重新对齐。
    if (_isComposerImeRangeOverflow(details.exception)) {
      debugLog(
        'openhand',
        'swallowed IME range overflow: ${details.exceptionAsString()}',
      );
      _triggerComposerImeSoftRecovery();
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
      debugLog('openhand', 'swallowed async error: $error');
      return true;
    }
    if (_isComposerImeRangeOverflow(error)) {
      _triggerComposerImeSoftRecovery();
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
                StructuredErrorText.format(
                  title: StructuredErrorText.pick(
                    zh: '数据库初始化失败',
                    en: 'Database initialization failed',
                  ),
                  reason: '$error',
                  try_: StructuredErrorText.pick(
                    zh:
                        '· 检查 Application Support 目录是否可写，以及是否被其他实例占用\n'
                        '· 检查磁盘剩余空间是否充足\n'
                        '· 退出其他 OpenHand 进程后再启动（sqlite 不允许同库多写）\n'
                        '· 必要时备份并删除 openhand.db，让程序重新建库',
                    en:
                        '· Check whether the Application Support directory is writable and whether another instance is using it\n'
                        '· Confirm that enough disk space is available\n'
                        '· Exit other OpenHand processes before starting again (sqlite does not allow concurrent writers to the same database)\n'
                        '· If needed, back up and remove openhand.db so the app can rebuild it',
                  ),
                ),
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
  final cronsModuleFuture = CronsModule.bootstrap();
  final hooksModuleFuture = HooksModule.bootstrap();
  final instructionsModuleFuture = InstructionsModule.bootstrap();
  final memoryModuleFuture = MemoryModule.bootstrap();
  final pluginServiceModuleFuture = PluginServiceModule.bootstrap();
  // 2026-05-24 — 预加载输出格式控制 Prompt 片段（fire-and-forget），
  // 实际渲染时 AiPromptBuilder 同步读取已缓存内容；未就绪时回退到内置兜底。
  unawaited(AiOutputFormatPrompts.ensureLoaded());
  // 2026-05-03: kick off system-proxy detection in parallel with the
  // controllers — internal HTTP clients (WebSearch / WebFetch) consult
  // SystemProxyResolver lazily, so this is purely best-effort.
  final systemProxyFuture = SystemProxyResolver.instance.initialize();

  developer.Timeline.startSync('openhand.boot.await_settings_hooks');
  final settingsController = await settingsControllerFuture;
  final hooks = await hooksModuleFuture;
  developer.Timeline.finishSync();
  // 2026-05-03 — settings 加载完成后立刻把代理偏好同步给 resolver；
  // 后续设置变更通过 listener 同步，全程不需要重启。
  SystemProxyResolver.instance.applyConfig(settingsController.proxySettings);
  settingsController.addListener(() {
    SystemProxyResolver.instance.applyConfig(settingsController.proxySettings);
  });
  // 2026-05-18 — 节流配置自动同步：开机后 1s 静默 pull，配置变更
  // debounce 5s 自动 push；provider != custom 或 endpoint 空时是 noop。
  ThrottleAutoSyncService(settingsController: settingsController).start();
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
  final aiModuleFuture = AiModule.bootstrap(
    userHooksExecutor: hooks.executor,
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
  final skillsModuleFuture = SkillsModule.bootstrap(
    initialStoragePath: settingsController.skillsStoragePath,
  );
  final mcpModuleFuture = McpModule.bootstrap(
    initialFilePath: settingsController.mcpServersFilePath,
    autoProbeConcurrency: settingsController.mcpAutoProbeConcurrency,
  );
  final skills = await skillsModuleFuture;
  unawaited(skills.controller.refresh());
  final mcp = await mcpModuleFuture;
  unawaited(mcp.controller.refresh());
  // 2026-04-25 boot perf — MemoryController is only consumed inside
  // user-action code paths (`_buildRuntimeContext` + self-learning sub-agent
  // tools), never at first paint of the home shell. Construct it
  // synchronously and refresh in the background so its sqlite load no
  // longer sits on the boot critical path.
  final memory = await memoryModuleFuture;
  unawaited(memory.controller.refresh());
  // 2026-04-25 boot perf — CronsController only matters once the user opens
  // the Crons view OR a scheduled tick fires. Construct it synchronously so
  // we can register the Hermes Talker agent handler before runApp, then run
  // the sqlite load + scheduler startup in the background. The agent
  // handler is a plain field setter and does not require initialize() to
  // have completed.
  final crons = await cronsModuleFuture;
  final cronsController = crons.controller;
  // 2026-04-25 — InstructionsController: 与 memory 同样“非首屏关键路径”，
  // 同步构造 + 后台 refresh，确保启动期间不阻塞首帧。
  // 2026-05-16 — 经 InstructionsModule.bootstrap 装配（即时完成的 Future，
  // 保留懒初始化语义）。
  final instructions = await instructionsModuleFuture;
  unawaited(instructions.controller.refresh());
  final appInfo = await appInfoFuture;
  AppRuntimeContext.initialize(appInfo, appLocale: settingsController.locale);
  settingsController.addListener(() {
    AppRuntimeContext.updateAppLocale(settingsController.locale);
  });
  developer.Timeline.startSync('openhand.boot.await_remaining_controllers');
  memoryControllerHandle = memory.controller;
  final ai = await aiModuleFuture;
  final aiSessionController = ai.controller;
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
    memoryController: memory.controller,
    llmDispatcher: buildSelfLearningDispatcher(
      chatClient: selfLearningChatClient,
      settingsController: settingsController,
      memoryController: memory.controller,
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
    if (entry.tags.contains(CronsController.mcpKeywordIndexTag)) {
      // 2026-05-04 — MCP 关键词倒排索引定时重建。复用 McpController 单飞构建器，
      // 与 UI 入口共享同一份磁盘缓存。失败由调度器统一记录，不需在此抛错。
      try {
        await mcp.controller.ensureKeywordIndexLoaded();
        final result = await mcp.controller.buildKeywordIndex();
        return AgentHandlerResult(
          stdout:
              'ok: servers=${result.index.totalServers} '
              'tools=${result.index.totalTools} '
              'skipped=${result.skippedServers} '
              'duration_ms=${result.index.durationMs}',
        );
      } catch (error, stack) {
        silentLog('main', 'mcp keyword index rebuild', error, stack);
        return AgentHandlerResult(stdout: 'error: $error');
      }
    }
    return AgentHandlerResult(
      stdout: 'noop: unknown agent tag (${entry.tags.join(",")})',
    );
  });
  settingsController.addListener(() {
    mcp.controller.updateAutoProbeConcurrency(
      settingsController.mcpAutoProbeConcurrency,
    );
    selfLearningScheduler.updateConcurrency(
      settingsController.selfLearningConcurrency,
    );
    SelfLearningRunner.streamFlushIntervalMs =
        settingsController.selfLearningStreamFlushIntervalMs;
    // 2026-05-04 — 同步 MCP 关键词倒排索引调度，复用同一条系统 cron 条目。
    unawaited(
      cronsController.updateMcpKeywordIndexSchedule(
        mode: settingsController.mcpKeywordIndexUpdateMode,
        intervalValue: settingsController.mcpKeywordIndexIntervalValue,
        intervalUnit: settingsController.mcpKeywordIndexIntervalUnit,
        scheduledTimeOfDay:
            settingsController.mcpKeywordIndexScheduledTimeOfDay,
      ),
    );
  });
  // 启动期同步一次，避免首次 listener 触发前的 race。
  SelfLearningRunner.streamFlushIntervalMs =
      settingsController.selfLearningStreamFlushIntervalMs;
  // Kick off the deferred cron init AFTER the agent handler is registered so
  // any immediate scheduler tick post-init can dispatch correctly.
  // 2026-05-04 — 串接：cron init 完成后立刻把当前设置项推一次到 MCP 关键词
  // 索引系统 cron 条目（listener 仅在 setter 触发，启动期需要主动同步一次）；
  // 同时启动期惰性加载磁盘缓存，避免首次手动构建命中 disk-empty。
  unawaited(mcp.controller.ensureKeywordIndexLoaded());
  unawaited(() async {
    await cronsController.initialize();
    await cronsController.updateMcpKeywordIndexSchedule(
      mode: settingsController.mcpKeywordIndexUpdateMode,
      intervalValue: settingsController.mcpKeywordIndexIntervalValue,
      intervalUnit: settingsController.mcpKeywordIndexIntervalUnit,
      scheduledTimeOfDay: settingsController.mcpKeywordIndexScheduledTimeOfDay,
    );
  }());

  final messageGateway = await MessageGatewayModule.bootstrap(
    sessionController: aiSessionController,
    settingsController: settingsController,
    skillsController: skills.controller,
    mcpController: mcp.controller,
    memoryController: memory.controller,
    cronsController: cronsController,
    instructionsController: instructions.controller,
    appInfo: appInfo,
  );
  unawaited(messageGateway.controller.initialize());

  final pluginService = await pluginServiceModuleFuture;
  unawaited(pluginService.controller.initialize());
  messageGateway.controller.pluginServiceController = pluginService.controller;

  // 2026-04-25 — 冷启动后异步触发一次 cron 历史清理（single-flight，
  // 永不抛异常，超时兜底 30s），不干扰主路径与 UI 启动。
  unawaited(
    runCronHistoryCleanupOnce(
      settings: settingsController,
      crons: cronsController,
    ),
  );

  // 2026-05 — WebSearch 缓存预热 / 自愈：扫描 ~/.openhand/cache/web_search/
  // 删除已过期、孤儿 entry 与孤儿 .txt，重建 index.json。fire-and-forget,
  // 全部失败 silentLog；不阻塞 UI 启动。
  unawaited(WebSearchCacheStore.instance.prewarm());
  unawaited(WebFetchCacheStore.instance.prewarm());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
        ...SkillsModule.providers(skills),
        ...McpModule.providers(mcp),
        ...HooksModule.providers(hooks),
        ...MemoryModule.providers(memory),
        ...CronsModule.providers(crons),
        ...InstructionsModule.providers(instructions),
        ...MessageGatewayModule.providers(messageGateway),
        ...PluginServiceModule.providers(pluginService),
        ...AiModule.providers(ai),
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
  } catch (error, stack) {
    silentLog('main', 'load AppInfo', error, stack);
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

/// 2026-06-02 — 识别 `TextEditingValue.fromJSON` / `TextRange` 选区越界断言。
/// framework 抛出的文案是 `Range start N is out of text of length M`，
/// 必伴随 `TextInputClient.updateEditingState` 上下文（来自
/// `_loudlyHandleTextInputInvocation`）。命中即交给 composer 软恢复处理。
bool _isComposerImeRangeOverflow(Object error) {
  if (error is AssertionError) {
    final message = error.message?.toString() ?? '';
    if (message.contains('is out of text of length')) {
      return true;
    }
  }
  final str = error.toString();
  return str.contains('TextInputClient.updateEditingState') &&
      str.contains('is out of text of length');
}

/// 2026-06-02 — 触发 composer 的轻量级 IME 软恢复。注册在
/// [InputRepairService] 上的钩子由 home page 在 `initState` 里挂上，做
/// `unfocus → scheduleMicrotask → requestFocus` 的最小重置，避免每次
/// 越界都跑 `InputRepairService.repair()` 的全流程。
void _triggerComposerImeSoftRecovery() {
  try {
    InputRepairService.instance.triggerSoftRecovery();
  } catch (error, stack) {
    silentLog('main', 'trigger composer ime soft recovery', error, stack);
  }
}

void _handleUncaughtZoneError(Object error, StackTrace stack) {
  if (_shouldSilenceRenderingError(error)) {
    debugLog('openhand', 'swallowed zone error: $error');
    return;
  }
  if (_isComposerImeRangeOverflow(error)) {
    _triggerComposerImeSoftRecovery();
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
