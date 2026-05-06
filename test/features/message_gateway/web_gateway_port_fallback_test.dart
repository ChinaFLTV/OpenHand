import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_info.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/crons/crons_controller.dart';
import 'package:openhand/features/instructions/instructions_controller.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/memory/memory_controller.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';
import 'package:openhand/features/message_gateway/service/web_message_platform_service.dart';
import 'package:openhand/features/skills/skills_controller.dart';
import 'package:openhand/shared/data/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'falls back to an available port when configured port is occupied',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'openhand-web-gateway-',
      );
      final ownsDatabase = !DatabaseService.isInitialized;
      final databaseService = await DatabaseService.initialize(
        databasePath: p.join(temp.path, 'openhand.db'),
        useNoIsolateFactory: true,
      );
      final occupiedServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final occupiedPort = occupiedServer.port;

      final sessionController = await AiSessionController.create(
        store: AiSessionStore(
          sessionsDirectoryPath: p.join(temp.path, 'sessions'),
        ),
      );
      final settingsController = await SettingsController.create(
        store: _InMemorySettingsStore(),
      );
      final service = WebMessagePlatformService(
        sessionController: sessionController,
        settingsController: settingsController,
        skillsController: SkillsController.uninitialized(
          initialStoragePath: p.join(temp.path, 'skills'),
        ),
        mcpController: McpController.uninitialized(
          initialFilePath: p.join(temp.path, 'mcp.json'),
        ),
        memoryController: MemoryController.uninitialized(),
        cronsController: CronsController.uninitialized(),
        instructionsController: InstructionsController.uninitialized(),
        appInfo: AppInfo.fallback(),
        cacheDirectoryPath: p.join(temp.path, 'cache'),
        logsDirectoryPath: p.join(temp.path, 'logs'),
        workspaceDirectoryPath: temp.path,
      );

      try {
        await service.start(
          WebMessagePlatformConfig(
            enabled: true,
            listenHost: InternetAddress.loopbackIPv4.address,
            listenPort: occupiedPort,
          ),
        );

        final boundPort = Uri.parse(service.boundUrl).port;
        expect(service.isRunning, isTrue);
        expect(boundPort, isNot(occupiedPort));
        expect(
          service.logs.any((entry) => entry.message.contains('已被占用')),
          isTrue,
        );
      } finally {
        await service.dispose();
        sessionController.dispose();
        settingsController.dispose();
        await occupiedServer.close(force: true);
        if (ownsDatabase) {
          await databaseService.close();
        }
        await temp.delete(recursive: true);
      }
    },
  );
}

class _InMemorySettingsStore extends SettingsStore {
  AppSettingsSnapshot _snapshot = AppSettingsSnapshot.defaults();

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: _snapshot);
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}
