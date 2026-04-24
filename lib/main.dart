import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'app/model/app_info.dart';
import 'app/openhand_app.dart';
import 'app/state/settings_controller.dart';
import 'app/support/app_runtime_context.dart';
import 'features/ai/ai_session_controller.dart';
import 'features/ai/service/ai_claude_hook_service.dart';
import 'features/ai/service/ai_protocol_adapter.dart' as ai_protocol_adapter;
import 'features/ai/service/lsp_client_service.dart';
import 'features/ai/service/self_learning_runner.dart';
import 'features/ai/service/self_learning_scheduler.dart';
import 'features/crons/crons_controller.dart';
import 'features/hooks/hooks_controller.dart';
import 'features/hooks/hooks_executor.dart';
import 'features/mcp/mcp_controller.dart';
import 'features/memory/memory_controller.dart';
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
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Text(
            'Database initialization failed.\n'
            'Please check disk permissions and available space.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
    return;
  }

  // Fire-and-forget cleanup of stale temp artifacts — never blocks startup
  // and never throws.
  unawaited(HooksExecutor.pruneStaleTempFiles());
  unawaited(ai_protocol_adapter.pruneInlineMediaCache());

  final settingsControllerFuture = SettingsController.create();
  final appInfoFuture = _loadAppInfo();
  final hooksControllerFuture = HooksController.create();

  final settingsController = await settingsControllerFuture;
  final hooksController = await hooksControllerFuture;
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
  final skillsControllerFuture = SkillsController.create(
    initialStoragePath: settingsController.skillsStoragePath,
  );
  final mcpControllerFuture = McpController.create(
    initialFilePath: settingsController.mcpServersFilePath,
  );
  final memoryControllerFuture = MemoryController.create();
  final cronsControllerFuture = CronsController.create();
  final appInfo = await appInfoFuture;
  AppRuntimeContext.initialize(appInfo);
  final skillsController = await skillsControllerFuture;
  final mcpController = await mcpControllerFuture;
  final memoryController = await memoryControllerFuture;
  memoryControllerHandle = memoryController;
  final cronsController = await cronsControllerFuture;
  final aiSessionController = await aiSessionControllerFuture;

  // 2026-04-25 Hermes Talker — bootstrap the self-learning scheduler + runner
  // and register the `agent` cron handler so the system-managed
  // `self_learning.hermes_talker` entry can fire every 5 minutes.
  final selfLearningRunner = SelfLearningRunner(
    sessionController: aiSessionController,
    memoryController: memoryController,
    // llmDispatcher is intentionally null in v1.0.0 — the scheduler/runner
    // still produces `selfLearning` cards (status=skipped) so the plumbing
    // is observable. Wiring a real restricted sub-agent requires a chat-
    // runtime hook and is tracked as a follow-up.
  );
  final selfLearningScheduler = SelfLearningScheduler(
    sessionStore: aiSessionController.store,
    memoryController: memoryController,
    settingsController: settingsController,
    promptRepository: aiSessionController.templateRepository,
    sessionController: aiSessionController,
    runForSession: selfLearningRunner.runForSession,
    concurrency: settingsController.selfLearningConcurrency,
  );
  cronsController.registerAgentHandler((entry) async {
    if (entry.tags.contains(CronsController.hermesTalkerTag)) {
      final result = await selfLearningScheduler.tick();
      return 'ok: scanned=${result.scanned} triggered=${result.triggered} '
          'skipped=${result.skipped} errors=${result.errors}';
    }
    return 'noop: unknown agent tag (${entry.tags.join(",")})';
  });
  settingsController.addListener(() {
    selfLearningScheduler.updateConcurrency(
      settingsController.selfLearningConcurrency,
    );
  });

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
        ChangeNotifierProvider<AiSessionController>.value(
          value: aiSessionController,
        ),
        Provider<AppInfo>.value(value: appInfo),
      ],
      child: const OpenHandApp(),
    ),
  );
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
