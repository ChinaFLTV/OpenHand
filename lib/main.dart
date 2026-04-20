import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'app/model/app_info.dart';
import 'app/openhand_app.dart';
import 'app/state/settings_controller.dart';
import 'app/support/app_runtime_context.dart';
import 'features/ai/ai_session_controller.dart';
import 'features/ai/service/ai_claude_hook_service.dart';
import 'features/ai/service/lsp_client_service.dart';
import 'features/hooks/hooks_controller.dart';
import 'features/hooks/hooks_executor.dart';
import 'features/crons/crons_controller.dart';
import 'features/mcp/mcp_controller.dart';
import 'features/memory/memory_controller.dart';
import 'features/skills/skills_controller.dart';
import 'shared/data/database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
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

  final settingsControllerFuture = SettingsController.create();
  final appInfoFuture = _loadAppInfo();
  final hooksControllerFuture = HooksController.create();

  final settingsController = await settingsControllerFuture;
  final hooksController = await hooksControllerFuture;
  final aiSessionControllerFuture = AiSessionController.create(
    hookService: AiClaudeHookService(),
    userHooksExecutor: HooksExecutor(controller: hooksController),
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
  final cronsController = await cronsControllerFuture;
  final aiSessionController = await aiSessionControllerFuture;

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
