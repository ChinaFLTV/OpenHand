import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'app/model/app_info.dart';
import 'app/openhand_app.dart';
import 'app/state/settings_controller.dart';
import 'features/ai/ai_session_controller.dart';
import 'features/ai/service/ai_claude_hook_service.dart';
import 'features/mcp/mcp_controller.dart';
import 'features/memory/memory_controller.dart';
import 'features/skills/skills_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsControllerFuture = SettingsController.create();
  final appInfoFuture = _loadAppInfo();
  final aiSessionControllerFuture = AiSessionController.create(
    hookService: AiClaudeHookService(),
  );

  final settingsController = await settingsControllerFuture;
  final skillsControllerFuture = SkillsController.create(
    initialStoragePath: settingsController.skillsStoragePath,
  );
  final mcpControllerFuture = McpController.create(
    initialFilePath: settingsController.mcpServersFilePath,
  );
  final memoryControllerFuture = MemoryController.create(
    initialFilePath: settingsController.userMemoryFilePath,
  );
  final appInfo = await appInfoFuture;
  final skillsController = await skillsControllerFuture;
  final mcpController = await mcpControllerFuture;
  final memoryController = await memoryControllerFuture;
  final aiSessionController = await aiSessionControllerFuture;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
        ChangeNotifierProvider<SkillsController>.value(value: skillsController),
        ChangeNotifierProvider<McpController>.value(value: mcpController),
        ChangeNotifierProvider<MemoryController>.value(value: memoryController),
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
