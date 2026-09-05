import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'app/model/app_info.dart';
import 'app/openhand_app.dart';
import 'app/state/settings_controller.dart';
import 'app/support/app_runtime_cleanup_registry.dart';
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
import 'features/machine_terminal/index.dart';
import 'features/mcp/index.dart';
import 'features/mcp/mcp_errors.dart';
import 'features/memory/index.dart';
import 'features/message_gateway/index.dart';
import 'features/plugin_service/index.dart';
import 'features/services/index.dart';
import 'features/settings/service/throttle_auto_sync_service.dart';
import 'features/skills/index.dart';
import 'features/thread_template_runtime/index.dart';
import 'features/workflows/index.dart';
import 'shared/db/database_service.dart';
import 'shared/fps/openhand_fps_monitor.dart';
import 'shared/ui/startup_failure_view.dart';
import 'shared/ui/structured_error_text.dart';
import 'shared/util/user_failure_message.dart';

Future<void> main() async {
  // 用 Zone 统一兜住异步异常，并过滤第三方库已知的可恢复输出噪声。
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
  final runtimeCleanup = AppRuntimeCleanupRegistry(
    cleanupTimeout: const Duration(seconds: 5),
    totalTimeout: kOpenHandApplicationRuntimeCleanupTotalTimeout,
  );
  try {
    await _bootstrapRuntime(runtimeCleanup);
  } catch (error, stack) {
    silentLog('main', '应用启动失败', error, stack);
    OpenHandFpsMonitor.instance.stop();
    runApp(
      OpenHandStartupFailureApp(
        title: StructuredErrorText.pick(
          zh: '应用启动失败',
          en: 'Application startup failed',
        ),
        reason: userFailureMessage(
          error,
          fallback: StructuredErrorText.pick(
            zh: '初始化运行时组件时发生异常。',
            en: 'An error occurred while initializing runtime components.',
          ),
        ),
        suggestionsTitle: StructuredErrorText.pick(
          zh: '建议处理',
          en: 'Recommended actions',
        ),
        suggestions: <String>[
          StructuredErrorText.pick(
            zh: '退出其他 OpenHand 进程后重新启动。',
            en: 'Exit other OpenHand processes and start again.',
          ),
          StructuredErrorText.pick(
            zh: '检查应用数据目录权限和磁盘剩余空间。',
            en: 'Check app data directory permissions and free disk space.',
          ),
          StructuredErrorText.pick(
            zh: '若问题持续，请查看运行日志中的首个启动异常。',
            en: 'If the issue persists, inspect the first startup error in the runtime log.',
          ),
        ],
      ),
    );
    _runMainBackgroundTask(() async {
      await runtimeCleanup.dispose();
      await killAllTrackedChildren();
    }(), '释放启动失败资源与子进程');
  }
}

Future<void> _bootstrapRuntime(AppRuntimeCleanupRegistry runtimeCleanup) async {
  MediaKit.ensureInitialized();
  iaw.PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  // 节流自动模式与 UI 卡顿降级会读取 recentFps。
  OpenHandFpsMonitor.instance.start();
  runtimeCleanup.register('FPS 监控器', OpenHandFpsMonitor.instance.stop);

  final originalOnError = FlutterError.onError;
  final originalPlatformOnError = PlatformDispatcher.instance.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_shouldSilenceHighlightFormattingError(
      details.exception,
      details.stack,
    )) {
      return;
    }
    if (_isRecoverableOverlayPortalHitTestRace(
      details.exception,
      details.stack,
    )) {
      return;
    }
    // 平台 IME 选区越界断言会在 reportError 后再次抛出；这里转为轻量恢复。
    if (_isComposerImeRangeOverflow(details.exception, details.stack)) {
      _triggerComposerImeSoftRecovery();
      return;
    }
    if (_shouldSilenceMcpLifecycleError(details.exception)) {
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

  // 吃掉平台分发器上报的可恢复异步异常，避免单次渲染噪声触发连续重建。
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_shouldSilenceHighlightFormattingError(error, stack)) {
      return true;
    }
    if (_isRecoverableOverlayPortalHitTestRace(error, stack)) {
      return true;
    }
    if (_isComposerImeRangeOverflow(error, stack)) {
      _triggerComposerImeSoftRecovery();
      return true;
    }
    if (_shouldSilenceMcpLifecycleError(error)) {
      return true;
    }
    return originalPlatformOnError?.call(error, stack) ?? false;
  };

  // 先初始化数据库，再创建依赖数据库的控制器。
  try {
    await DatabaseService.initialize();
  } catch (error, stackTrace) {
    silentLog('main', '数据库初始化失败', error, stackTrace);
    final reason = userFailureMessage(
      error,
      fallback: StructuredErrorText.pick(
        zh: '无法初始化应用数据库，请检查目录权限和磁盘空间。',
        en: 'Unable to initialize the application database. Check directory permissions and free disk space.',
      ),
    );
    runApp(
      OpenHandStartupFailureApp(
        title: StructuredErrorText.pick(
          zh: '数据库初始化失败',
          en: 'Database initialization failed',
        ),
        reason: reason,
        suggestionsTitle: StructuredErrorText.pick(
          zh: '建议处理',
          en: 'Recommended actions',
        ),
        suggestions: [
          StructuredErrorText.pick(
            zh: '检查 Application Support 目录是否可写，以及是否被其他实例占用。',
            en: 'Check whether the Application Support directory is writable or used by another instance.',
          ),
          StructuredErrorText.pick(
            zh: '确认磁盘剩余空间充足。',
            en: 'Confirm that enough disk space is available.',
          ),
          StructuredErrorText.pick(
            zh: '退出其他 OpenHand 进程后重新启动。',
            en: 'Exit other OpenHand processes and start again.',
          ),
          StructuredErrorText.pick(
            zh: '必要时备份并删除 openhand.db，让应用重新建库。',
            en: 'If needed, back up and remove openhand.db so the app can rebuild it.',
          ),
        ],
      ),
    );
    _runMainBackgroundTask(() async {
      await runtimeCleanup.dispose();
      await killAllTrackedChildren();
    }(), '释放数据库启动失败资源与子进程');
    return;
  }
  runtimeCleanup.register('数据库', DatabaseService.instance.close);

  final settingsControllerFuture = SettingsController.create();
  final appInfoFuture = _loadAppInfo();
  final cronsModuleFuture = CronsModule.bootstrap();
  final hooksModuleFuture = HooksModule.bootstrap();
  final instructionsModuleFuture = InstructionsModule.bootstrap();
  final memoryModuleFuture = MemoryModule.bootstrap();
  final servicesModuleFuture = ServicesModule.bootstrap();
  final pluginServiceModuleFuture = PluginServiceModule.bootstrap();
  final knowledgeBaseModuleFuture = KnowledgeBaseModule.bootstrap();
  final workflowsModuleFuture = WorkflowsModule.bootstrap();
  // 预加载输出格式控制 Prompt 片段；未就绪时 AiPromptBuilder 会回退到内置兜底。
  _runMainBackgroundTask(AiOutputFormatPrompts.ensureLoaded(), '加载输出格式 Prompt');
  // 后台恢复已同步的 OpenRouter 模型档案，不阻塞首帧启动。
  _runMainBackgroundTask(
    OpenRouterModelProfileStore.instance.ensureLoaded(),
    '加载 OpenRouter 模型参数',
  );
  // 系统代理检测与控制器并行启动；内部 HTTP 客户端会按需读取结果。
  final systemProxyFuture = SystemProxyResolver.instance.initialize();

  developer.Timeline.startSync('openhand.boot.await_settings_hooks');
  final settingsController = await settingsControllerFuture;
  runtimeCleanup.register('设置控制器', settingsController.shutdown);
  final hooks = await hooksModuleFuture;
  runtimeCleanup.register('Hooks 控制器', hooks.controller.shutdown);
  developer.Timeline.finishSync();
  // 启动阶段先写入一次；统一监听器会在所有运行时依赖就绪后注册。
  SystemProxyResolver.instance.applyConfig(settingsController.proxySettings);
  // 用顶层变量把 stdio MCP 镜像源模式同步给发现服务。
  mcpStdioMirrorModeOverride = settingsController.mcpStdioMirrorMode;
  // MemoryController 懒加载完成后再暴露给 AI 内建 Memory 工具。
  MemoryController? memoryControllerHandle;
  KnowledgeBaseController? knowledgeBaseControllerHandle;
  final machineTerminalService = MachineTerminalService();
  final machineTerminalFileService = MachineTerminalFileService(
    machineTerminalService,
  );
  runtimeCleanup
    ..register('机器终端服务', () async {
      await machineTerminalService.shutdown();
      machineTerminalService.dispose();
    }, timeout: MachineTerminalService.runtimeCleanupTimeout)
    ..register('机器终端文件服务', () async {
      await machineTerminalFileService.shutdown();
      machineTerminalFileService.dispose();
    }, timeout: MachineTerminalFileService.runtimeCleanupTimeout);
  final aiModuleFuture = AiModule.bootstrap(
    userHooksExecutor: hooks.executor,
    skillsDirProvider: () => settingsController.skillsStoragePath,
    memoryControllerProvider: () => memoryControllerHandle,
    aiModelsProvider: () => settingsController.aiModels,
    knowledgeBaseControllerProvider: () => knowledgeBaseControllerHandle,
    machineTerminalService: machineTerminalService,
  );
  AiLspClientService.instance.updateLanguageSettings(
    settingsController.editorLspSettings,
  );
  final skillsModuleFuture = SkillsModule.bootstrap(
    initialStoragePath: settingsController.skillsStoragePath,
  );
  final mcpModuleFuture = McpModule.bootstrap(
    initialFilePath: settingsController.mcpServersFilePath,
    autoProbeConcurrency: settingsController.mcpAutoProbeConcurrency,
  );
  final skills = await skillsModuleFuture;
  runtimeCleanup.register('技能控制器', skills.controller.shutdown);
  _runMainBackgroundTask(skills.controller.refresh(), '刷新技能');
  final mcp = await mcpModuleFuture;
  runtimeCleanup.register(
    'MCP 控制器',
    mcp.controller.shutdown,
    timeout: McpController.runtimeCleanupTimeout,
  );
  _runMainBackgroundTask(mcp.controller.ensureRuntimeReady(), '恢复 MCP 运行时');
  // MemoryController 只在用户动作路径使用，刷新放到后台以缩短冷启动关键路径。
  final memory = await memoryModuleFuture;
  runtimeCleanup.register('记忆控制器', memory.controller.shutdown);
  _runMainBackgroundTask(memory.controller.refresh(), '刷新记忆');
  final services = await servicesModuleFuture;
  runtimeCleanup
    ..register('AI 模型中转站控制器', services.aiModelProxyController.shutdown)
    ..register('AI 模型健康巡检控制器', services.aiModelHealthController.dispose)
    ..register('扫描服务控制器', services.controller.shutdown);
  services.aiModelProxyController.attachModelsProvider(
    () => settingsController.aiModels,
  );
  services.aiModelHealthController.attachModelsProvider(
    () => settingsController.aiModels,
  );
  services.aiModelHealthController.attachProxyResolver(
    ({required String targetHost}) => services.aiModelProxyController
        .resolveProxyEndpoint(targetHost: targetHost),
  );
  services.aiModelProxyController.attachThemeProvider(
    () => (
      themeMode: settingsController.themeMode,
      preset: settingsController.themePreset,
      locale: settingsController.locale,
      dialogAnimation: settingsController.dialogAnimationSettings,
      reduceMotion: settingsController.reduceMotion,
    ),
  );
  settingsController.attachAiModelProviderEndpointGuard(
    services.aiModelProxyController.isSelfProxyBaseUrl,
  );
  services.controller.attachSelectedAiModelProvider(
    () => settingsController.selectedAiModel,
  );
  // CronsController 先注册托管任务处理器，再把数据库加载和调度器启动放到后台。
  final crons = await cronsModuleFuture;
  final cronsController = crons.controller;
  runtimeCleanup.register('定时任务控制器', cronsController.shutdown);
  // InstructionsController 不是首屏关键路径，后台刷新即可。
  final instructions = await instructionsModuleFuture;
  runtimeCleanup.register('指令控制器', instructions.controller.shutdown);
  _runMainBackgroundTask(instructions.controller.refresh(), '刷新指令');
  final appInfo = await appInfoFuture;
  AppRuntimeContext.initialize(appInfo);
  developer.Timeline.startSync('openhand.boot.await_remaining_controllers');
  memoryControllerHandle = memory.controller;
  final ai = await aiModuleFuture;
  final aiSessionController = ai.controller;
  runtimeCleanup
    ..register(
      'AI 会话存储',
      aiSessionController.store.flush,
      timeout: AiSessionStore.runtimeCleanupTimeout,
    )
    ..register(
      'AI 会话控制器',
      aiSessionController.shutdown,
      timeout: AiSessionController.runtimeCleanupTimeout,
    );
  developer.Timeline.finishSync();
  // 后台完成系统代理检测，失败时网络客户端继续直连。
  _runMainBackgroundTask(systemProxyFuture, '初始化系统代理');

  // 自学习调度器只暴露 Memory / SkillManager 工具，并把流式过程写入自学习卡片。
  final selfLearningChatClient = AiChatService();
  runtimeCleanup.register('自学习聊天客户端', selfLearningChatClient.dispose);
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
  cronsController.registerTaskHandler((entry) async {
    if (entry.tags.contains(CronsController.hermesTalkerTag)) {
      final result = await selfLearningScheduler.tick();
      final stdout =
          '完成：扫描=${result.scanned} 触发=${result.triggered} '
          '跳过=${result.skipped} 错误=${result.errors}';
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
        // JSON 编码失败时降级为纯标准输出，保留诊断线索但不影响调度链路。
        silentLog('main', '编码 Hermes Talker 上下文', error, stack);
      }
      return CronTaskHandlerResult(stdout: stdout, appContext: appContext);
    }
    if (entry.tags.contains(CronsController.mcpKeywordIndexTag)) {
      // 复用 McpController 单飞构建器，与 UI 入口共享同一份磁盘缓存。
      try {
        await mcp.controller.ensureKeywordIndexLoaded();
        final result = await mcp.controller.buildKeywordIndex();
        return CronTaskHandlerResult(
          stdout:
              '完成：服务=${result.index.totalServers} '
              '工具=${result.index.totalTools} '
              '跳过服务=${result.skippedServers} '
              '耗时毫秒=${result.index.durationMs}',
        );
      } catch (error, stack) {
        silentLog('main', '重建 MCP 关键词索引', error, stack);
        return CronTaskHandlerResult(
          stdout: '错误：${mcpFailureMessage(error, fallback: '重建 MCP 关键词索引失败。')}',
        );
      }
    }
    return CronTaskHandlerResult(
      stdout: '未处理：未知系统托管任务标签（${entry.tags.join(",")}）',
    );
  });
  void syncRuntimeSettings() {
    SystemProxyResolver.instance.applyConfig(settingsController.proxySettings);
    mcpStdioMirrorModeOverride = settingsController.mcpStdioMirrorMode;
    AiLspClientService.instance.updateLanguageSettings(
      settingsController.editorLspSettings,
    );
    mcp.controller.updateAutoProbeConcurrency(
      settingsController.mcpAutoProbeConcurrency,
    );
    selfLearningScheduler.updateConcurrency(
      settingsController.selfLearningConcurrency,
    );
    SelfLearningRunner.streamFlushIntervalMs =
        settingsController.selfLearningStreamFlushIntervalMs;
    AiUsageTracker.instance.updateEstimatedCharactersPerToken(
      settingsController.aiEstimatedCharactersPerToken,
    );
    _runMainBackgroundTask(
      cronsController.updateMcpKeywordIndexSchedule(
        mode: settingsController.mcpKeywordIndexUpdateMode,
        intervalValue: settingsController.mcpKeywordIndexIntervalValue,
        intervalUnit: settingsController.mcpKeywordIndexIntervalUnit,
        scheduledTimeOfDay:
            settingsController.mcpKeywordIndexScheduledTimeOfDay,
      ),
      '更新 MCP 关键词索引计划',
    );
  }

  settingsController.addListener(syncRuntimeSettings);
  // 启动期同步一次，避免首次监听器触发前出现竞态。
  SelfLearningRunner.streamFlushIntervalMs =
      settingsController.selfLearningStreamFlushIntervalMs;
  AiUsageTracker.instance.updateEstimatedCharactersPerToken(
    settingsController.aiEstimatedCharactersPerToken,
  );
  // 托管任务处理器注册后再初始化 cron；启动期主动同步一次 MCP 关键词索引计划。
  _runMainBackgroundTask(() async {
    await cronsController.initialize();
    await cronsController.updateMcpKeywordIndexSchedule(
      mode: settingsController.mcpKeywordIndexUpdateMode,
      intervalValue: settingsController.mcpKeywordIndexIntervalValue,
      intervalUnit: settingsController.mcpKeywordIndexIntervalUnit,
      scheduledTimeOfDay: settingsController.mcpKeywordIndexScheduledTimeOfDay,
    );
  }(), '初始化定时任务');

  final knowledgeBase = await knowledgeBaseModuleFuture;
  final workflows = await workflowsModuleFuture;
  runtimeCleanup
    ..register('知识库控制器', knowledgeBase.controller.shutdown)
    ..register('工作流控制器', workflows.controller.dispose);
  knowledgeBaseControllerHandle = knowledgeBase.controller;
  mcp.controller.attachOpsRuntimeBindings(
    McpOpsRuntimeBindings(
      builtinToolConfigsProvider: () => settingsController.builtinToolConfigs,
      skillsControllerProvider: () => skills.controller,
      memoryControllerProvider: () => memory.controller,
      instructionsControllerProvider: () => instructions.controller,
      knowledgeBaseControllerProvider: () => knowledgeBase.controller,
      toolRuntimeServiceProvider: () => aiSessionController.toolRuntimeService,
      opsModelProvider: () {
        final models = settingsController.aiModels;
        return models.isEmpty ? null : models.first;
      },
    ),
  );
  final pluginService = await pluginServiceModuleFuture;
  runtimeCleanup.register(
    '插件服务控制器',
    pluginService.controller.shutdown,
    timeout: PluginServiceController.runtimeCleanupTimeout,
  );
  final messageGateway = await MessageGatewayModule.bootstrap(
    MessageGatewayDependencies(
      sessionController: aiSessionController,
      settingsController: settingsController,
      skillsController: skills.controller,
      mcpController: mcp.controller,
      memoryController: memory.controller,
      cronsController: cronsController,
      hooksController: hooks.controller,
      instructionsController: instructions.controller,
      knowledgeBaseController: knowledgeBase.controller,
      workflowsController: workflows.controller,
      machineTerminalService: machineTerminalService,
      appInfo: appInfo,
    ),
  );
  runtimeCleanup.register('消息网关控制器', () async {
    messageGateway.controller.pluginServiceController = null;
    await messageGateway.controller.shutdown();
  }, timeout: MessageGatewayController.runtimeCleanupTimeout);
  _runMainBackgroundTask(messageGateway.controller.initialize(), '初始化消息网关');

  services.controller.attachPluginServiceController(pluginService.controller);
  // 中转站配置为启用时恢复真实 HTTP 监听；只有绑定成功后控制器才会显示运行中。
  if (services.aiModelProxyController.settings.enabled) {
    _runMainBackgroundTask(
      services.aiModelProxyController.start(),
      '恢复 AI 模型中转站监听',
    );
  }
  _runMainBackgroundTask(pluginService.controller.initialize(), '初始化插件服务');
  messageGateway.controller.pluginServiceController = pluginService.controller;
  _runMainBackgroundTask(knowledgeBase.controller.initialize(), '初始化知识库');

  // 冷启动后异步触发一次 cron 历史清理，不干扰 UI 启动。
  _runMainBackgroundTask(
    runCronHistoryCleanupOnce(
      settings: settingsController,
      crons: cronsController,
    ),
    '清理定时任务历史',
  );

  // 首帧前启动缓存预热与自愈，后台清理过期或孤立条目。
  _runMainBackgroundTask(
    WebSearchCacheStore.instance.prewarm(),
    '预热 WebSearch 缓存',
  );
  _runMainBackgroundTask(
    WebFetchCacheStore.instance.prewarm(),
    '预热 WebFetch 缓存',
  );
  _runMainBackgroundTask(MediaCacheService.instance.prewarm(), '预热媒体缓存');
  final templateRuntimeLinkageController = TemplateRuntimeLinkageController();
  runtimeCleanup.register(
    '模板运行时联动控制器',
    templateRuntimeLinkageController.dispose,
  );
  final throttleAutoSyncService = ThrottleAutoSyncService(
    settingsController: settingsController,
  );
  runtimeCleanup.register('节流自动同步服务', throttleAutoSyncService.dispose);
  throttleAutoSyncService.start();

  // 进程级资源统一登记，退出时按逆序有界释放；启动中断也会清理已登记资源。
  runtimeCleanup
    ..register(
      'AI 使用统计',
      AiUsageTracker.instance.shutdown,
      timeout: AiUsageTracker.runtimeCleanupTimeout,
    )
    ..register(
      'AI 工具调用统计',
      AiToolUsagePromotionStore.shared.shutdown,
      timeout: AiToolUsagePromotionStore.runtimeCleanupTimeout,
    )
    ..register('AI LSP 会话', AiLspClientService.instance.disposeAll)
    ..register('WebSearch 持久化', () async {
      await Future.wait<void>(<Future<void>>[
        WebSearchCacheStore.instance.shutdown(),
        WebSearchTelemetryStore.instance.shutdown(),
      ]);
    }, timeout: WebEngineCacheStoreBase.runtimeCleanupTimeout)
    ..register('WebFetch 持久化', () async {
      await Future.wait<void>(<Future<void>>[
        WebFetchCacheStore.instance.shutdown(),
        WebFetchTelemetryStore.instance.shutdown(),
      ]);
    }, timeout: WebEngineCacheStoreBase.runtimeCleanupTimeout)
    ..register(
      '媒体缓存',
      MediaCacheService.instance.shutdown,
      timeout: MediaCacheService.runtimeCleanupTimeout,
    )
    ..register(
      '离线语音模型服务',
      OfflineSpeechModelService.shutdownInstance,
      timeout: OfflineSpeechModelService.runtimeCleanupTimeout,
    );
  runtimeCleanup
    ..register('定时任务托管处理器', () => cronsController.registerTaskHandler(null))
    ..register(
      '运行时设置监听器',
      () => settingsController.removeListener(syncRuntimeSettings),
    );

  // 所有资源登记完成后再安装信号监听，避免启动期信号先锁定注册表，
  // 导致后续资源无法登记或清理。
  if (!Platform.isWindows) {
    Future<void>? signalShutdownFuture;
    Future<void> shutdownForSignal() {
      return signalShutdownFuture ??= () async {
        try {
          await runtimeCleanup.dispose();
        } catch (error, stack) {
          silentLog('main', '信号触发后释放运行时资源', error, stack);
        }
        try {
          await killAllTrackedChildren();
        } catch (error, stack) {
          silentLog('main', '信号触发后清理子进程', error, stack);
        }
        exit(0);
      }();
    }

    for (final sig in <ProcessSignal>[
      ProcessSignal.sigint,
      ProcessSignal.sigterm,
    ]) {
      try {
        final subscription = sig.watch().listen(
          (_) => unawaited(shutdownForSignal()),
        );
        runtimeCleanup.register('进程信号订阅', subscription.cancel);
      } catch (error, stack) {
        // 某些沙箱 / 测试环境不允许安装信号处理器，忽略。
        silentLog('main', '安装信号处理器', error, stack);
      }
    }
  }

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
        ...ServicesModule.providers(services),
        ...CronsModule.providers(crons),
        ...InstructionsModule.providers(instructions),
        ...MessageGatewayModule.providers(messageGateway),
        ...PluginServiceModule.providers(pluginService),
        ...KnowledgeBaseModule.providers(knowledgeBase),
        ...WorkflowsModule.providers(workflows),
        ...AiModule.providers(ai),
        ChangeNotifierProvider<MachineTerminalService>.value(
          value: machineTerminalService,
        ),
        ChangeNotifierProvider<MachineTerminalFileService>.value(
          value: machineTerminalFileService,
        ),
        ChangeNotifierProvider<TemplateRuntimeLinkageController>.value(
          value: templateRuntimeLinkageController,
        ),
        Provider<AppInfo>.value(value: appInfo),
      ],
      child: OpenHandApp(onShutdown: runtimeCleanup.dispose),
    ),
  );
  developer.Timeline.instantSync('openhand.boot.runApp_called');

  // 首帧后再清理过期临时文件，避免干扰启动期关键路径。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _runMainBackgroundTask(HooksExecutor.pruneStaleTempFiles(), '清理 Hook 临时文件');
    _runMainBackgroundTask(
      ai_protocol_adapter.pruneInlineMediaCache(),
      '清理内联媒体缓存',
    );
  });
}

void _runMainBackgroundTask<T>(Future<T> task, String action) {
  unawaited(
    task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        silentLog('main', action, error, stack);
      },
    ),
  );
}

Future<AppInfo> _loadAppInfo() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    return AppInfo.fromPackageInfo(packageInfo);
  } catch (error, stack) {
    silentLog('main', '加载 AppInfo', error, stack);
    return AppInfo.fallback();
  }
}

/// 仅过滤 highlight 已知的数字解析噪声，其他格式异常必须继续上报。
bool _shouldSilenceHighlightFormattingError(Object error, StackTrace? stack) {
  final message = error.toString();
  final isKnownFormattingNoise =
      message.contains('FormatException: Invalid number') ||
      message.contains('FormatException: Invalid radix-10 number') ||
      message.contains('FormatException: Invalid radix-16 number');
  if (!isKnownFormattingNoise) return false;
  final trace = stack?.toString() ?? '';
  return trace.contains('package:highlight/') ||
      trace.contains('package:flutter_highlight/');
}

/// 过滤 highlight 格式化异常和 media_kit 初始化跟踪输出，避免刷屏和首屏卡顿。
bool _shouldSilencePrintLine(String line) {
  return line.contains('FormatException: Invalid number') ||
      line.contains('FormatException: Invalid radix-10 number') ||
      line.contains('FormatException: Invalid radix-16 number') ||
      line.startsWith('media_kit: NativeReferenceHolder: Allocated ') ||
      line.startsWith('media_kit: NativeReferenceHolder: Located ');
}

/// Flutter 3.41 的浮层 / 弹窗子树在关闭、滚动或路由切换的同一帧里，
/// 偶发先被 MouseTracker / Gesture 命中测试扫到，随后才完成或移除布局。
/// 它只影响这一个指针包，不代表业务 RenderBox 约束错误；普通布局错误
/// 仍继续上报。
bool _isRecoverableOverlayPortalHitTestRace(Object error, StackTrace? stack) {
  final message = error.toString();
  final trace = stack?.toString() ?? '';
  final isPointerHitTestTrace =
      trace.contains('RenderBox.hitTest') &&
      trace.contains('package:flutter/src/widgets/overlay.dart') &&
      (trace.contains('MouseTracker') ||
          trace.contains('GestureBinding._handlePointerDataPacket'));
  if (!isPointerHitTestTrace) {
    return false;
  }

  if (message.contains(
    'Cannot hit test a render box that has never been laid out.',
  )) {
    return message.contains('_RenderDeferredLayoutBox') &&
        message.contains('NEEDS-LAYOUT');
  }

  if (message.contains('Cannot hit test a render box with no size.')) {
    return message.contains('RenderConstrainedBox') &&
        message.contains('BoxConstraints(280.0<=w<=Infinity');
  }

  return false;
}

/// 识别 TextInput 选区越界断言，命中即交给 composer 软恢复处理。
bool _isComposerImeRangeOverflow(Object error, StackTrace? stack) {
  final message = error is AssertionError
      ? error.message?.toString() ?? error.toString()
      : error.toString();
  if (!message.contains('is out of text of length')) return false;
  if (message.contains('TextInputClient.updateEditingState')) return true;
  final trace = stack?.toString() ?? '';
  return trace.contains('package:flutter/src/services/text_input.dart') ||
      trace.contains('package:flutter/src/widgets/editable_text.dart');
}

/// 触发 composer 的轻量级 IME 软恢复，避免每次越界都跑完整 repair 流程。
void _triggerComposerImeSoftRecovery() {
  try {
    InputRepairService.instance.triggerSoftRecovery();
  } catch (error, stack) {
    silentLog('main', '触发 composer IME 软恢复', error, stack);
  }
}

void _handleUncaughtZoneError(Object error, StackTrace stack) {
  if (_shouldSilenceHighlightFormattingError(error, stack)) {
    return;
  }
  if (_isRecoverableOverlayPortalHitTestRace(error, stack)) {
    return;
  }
  if (_isComposerImeRangeOverflow(error, stack)) {
    _triggerComposerImeSoftRecovery();
    return;
  }
  if (_shouldSilenceMcpLifecycleError(error)) {
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

bool _shouldSilenceMcpLifecycleError(Object error) {
  return isExpectedMcpToolDiscoveryLifecycleError(error);
}
