import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:media_kit/media_kit.dart';
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
import 'features/knowledge_base/index.dart';
import 'features/mcp/index.dart';
import 'features/memory/index.dart';
import 'features/message_gateway/index.dart';
import 'features/plugin_service/index.dart';
import 'features/settings/service/throttle_auto_sync_service.dart';
import 'features/skills/index.dart';
import 'features/thread_template_runtime/index.dart';
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
  MediaKit.ensureInitialized();
  iaw.PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  // 节流自动模式与 UI 卡顿降级会读取 recentFps。
  OpenHandFpsMonitor.instance.start();

  // 异常退出时先清理登记过的子进程，避免残留进程继续持有系统输入上下文。
  // 正常退出由 OpenHandApp 内的 AppLifecycleListener 处理。
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
      return;
    }
    if (_isRecoverableOverlayPortalHitTestRace(
      details.exception,
      details.stack,
    )) {
      return;
    }
    // 平台 IME 选区越界断言会在 reportError 后再次抛出；这里转为轻量恢复。
    if (_isComposerImeRangeOverflow(details.exception)) {
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
      return true;
    }
    if (_isRecoverableOverlayPortalHitTestRace(error, stack)) {
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
  final knowledgeBaseModuleFuture = KnowledgeBaseModule.bootstrap();
  // 预加载输出格式控制 Prompt 片段；未就绪时 AiPromptBuilder 会回退到内置兜底。
  unawaited(AiOutputFormatPrompts.ensureLoaded());
  // 2026-05-03: kick off system-proxy detection in parallel with the
  // controllers — internal HTTP clients (WebSearch / WebFetch) consult
  // SystemProxyResolver lazily, so this is purely best-effort.
  final systemProxyFuture = SystemProxyResolver.instance.initialize();

  developer.Timeline.startSync('openhand.boot.await_settings_hooks');
  final settingsController = await settingsControllerFuture;
  final hooks = await hooksModuleFuture;
  developer.Timeline.finishSync();
  // 设置变更通过 listener 同步给代理 resolver，全程不需要重启。
  SystemProxyResolver.instance.applyConfig(settingsController.proxySettings);
  settingsController.addListener(() {
    SystemProxyResolver.instance.applyConfig(settingsController.proxySettings);
  });
  // 节流配置自动同步：开机静默 pull，配置变更后 debounce push。
  ThrottleAutoSyncService(settingsController: settingsController).start();
  // 用 top-level 变量把 stdio MCP 镜像源模式同步给 discovery service。
  mcpStdioMirrorModeOverride = settingsController.mcpStdioMirrorMode;
  settingsController.addListener(() {
    mcpStdioMirrorModeOverride = settingsController.mcpStdioMirrorMode;
  });
  // MemoryController 懒加载完成后再暴露给 AI 内建 Memory 工具。
  MemoryController? memoryControllerHandle;
  KnowledgeBaseController? knowledgeBaseControllerHandle;
  final aiModuleFuture = AiModule.bootstrap(
    userHooksExecutor: hooks.executor,
    skillsDirProvider: () => settingsController.skillsStoragePath,
    memoryControllerProvider: () => memoryControllerHandle,
    aiModelsProvider: () => settingsController.aiModels,
    knowledgeBaseControllerProvider: () => knowledgeBaseControllerHandle,
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
  // MemoryController 只在用户动作路径使用，刷新放到后台以缩短冷启动关键路径。
  final memory = await memoryModuleFuture;
  unawaited(memory.controller.refresh());
  // CronsController 先注册 agent handler，再把数据库加载和调度器启动放到后台。
  final crons = await cronsModuleFuture;
  final cronsController = crons.controller;
  // InstructionsController 不是首屏关键路径，后台刷新即可。
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

  // 自学习调度器只暴露 Memory / SkillManager 工具，并把流式过程写入自学习卡片。
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
      // 复用 McpController 单飞构建器，与 UI 入口共享同一份磁盘缓存。
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
  // agent handler 注册后再初始化 cron；启动期主动同步一次 MCP 关键词索引计划。
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

  final knowledgeBase = await knowledgeBaseModuleFuture;
  knowledgeBaseControllerHandle = knowledgeBase.controller;
  final messageGateway = await MessageGatewayModule.bootstrap(
    sessionController: aiSessionController,
    settingsController: settingsController,
    skillsController: skills.controller,
    mcpController: mcp.controller,
    memoryController: memory.controller,
    cronsController: cronsController,
    instructionsController: instructions.controller,
    knowledgeBaseController: knowledgeBase.controller,
    appInfo: appInfo,
  );
  unawaited(messageGateway.controller.initialize());

  final pluginService = await pluginServiceModuleFuture;
  unawaited(pluginService.controller.initialize());
  messageGateway.controller.pluginServiceController = pluginService.controller;
  unawaited(knowledgeBase.controller.initialize());

  // 冷启动后异步触发一次 cron 历史清理，不干扰 UI 启动。
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
  final templateRuntimeLinkageController = TemplateRuntimeLinkageController();

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
        ...KnowledgeBaseModule.providers(knowledgeBase),
        ...AiModule.providers(ai),
        ChangeNotifierProvider<TemplateRuntimeLinkageController>.value(
          value: templateRuntimeLinkageController,
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

/// Flutter 3.41 的 [OverlayPortal] 延迟布局子树在 Tooltip/MenuAnchor 等
/// 浮层关闭、滚动或路由切换的同一帧里，偶发先被 MouseTracker / Gesture
/// hit test 扫到，随后才完成或移除布局。它只影响这一个指针包，不代表业务
/// RenderBox 约束错误；普通 "never laid out" 仍继续上报。
bool _isRecoverableOverlayPortalHitTestRace(Object error, StackTrace? stack) {
  final message = error.toString();
  if (!message.contains(
    'Cannot hit test a render box that has never been laid out.',
  )) {
    return false;
  }
  if (!message.contains('_RenderDeferredLayoutBox') ||
      !message.contains('NEEDS-LAYOUT')) {
    return false;
  }
  final trace = stack?.toString() ?? '';
  return trace.contains('package:flutter/src/widgets/overlay.dart') &&
      trace.contains('RenderBox.hitTest');
}

/// 识别 TextInput 选区越界断言，命中即交给 composer 软恢复处理。
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

/// 触发 composer 的轻量级 IME 软恢复，避免每次越界都跑完整 repair 流程。
void _triggerComposerImeSoftRecovery() {
  try {
    InputRepairService.instance.triggerSoftRecovery();
  } catch (error, stack) {
    silentLog('main', 'trigger composer ime soft recovery', error, stack);
  }
}

void _handleUncaughtZoneError(Object error, StackTrace stack) {
  if (_shouldSilenceRenderingError(error)) {
    return;
  }
  if (_isRecoverableOverlayPortalHitTestRace(error, stack)) {
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
