import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/features/ai/model/ai_allow_command_rule.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';

void main() {
  test('SettingsController persists deny command rules', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_settings_ai_rules_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final settingsFilePath = p.join(
      tempDirectory.path,
      '.openhand',
      'settings',
      'SETTINGS.toml',
    );
    final controller = await SettingsController.create(
      store: SettingsStore(settingsFilePath: settingsFilePath),
    );

    expect(
      await controller.addAiDenyCommandRule(
        const AiDenyCommandRule(
          id: 'rule-1',
          pattern: 'rm *',
          matchMode: AiDenyCommandMatchMode.simple,
          note: 'block file deletion',
        ),
      ),
      isTrue,
    );

    final reloadedController = await SettingsController.create(
      store: SettingsStore(settingsFilePath: settingsFilePath),
    );

    expect(reloadedController.aiDenyCommandRules, hasLength(1));
    expect(reloadedController.aiDenyCommandRules.first.pattern, 'rm *');
    expect(
      reloadedController.aiDenyCommandRules.first.matchMode,
      AiDenyCommandMatchMode.simple,
    );
  });

  test('SettingsController persists allow command rules', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_settings_ai_allow_rules_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final settingsFilePath = p.join(
      tempDirectory.path,
      '.openhand',
      'settings',
      'SETTINGS.toml',
    );
    final controller = await SettingsController.create(
      store: SettingsStore(settingsFilePath: settingsFilePath),
    );

    expect(
      await controller.addAiAllowCommandRule(
        const AiAllowCommandRule(
          id: 'allow-1',
          pattern: 'flutter test *',
          matchMode: AiDenyCommandMatchMode.simple,
          note: 'allow stable test runs',
        ),
      ),
      isTrue,
    );

    final reloadedController = await SettingsController.create(
      store: SettingsStore(settingsFilePath: settingsFilePath),
    );

    expect(reloadedController.aiAllowCommandRules, hasLength(1));
    expect(
      reloadedController.aiAllowCommandRules.first.pattern,
      'flutter test *',
    );
    expect(
      reloadedController.aiAllowCommandRules.first.matchMode,
      AiDenyCommandMatchMode.simple,
    );
  });

  test(
    'SettingsController persists the per-response tool call limit',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_settings_tool_call_limit_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final settingsFilePath = p.join(
        tempDirectory.path,
        '.openhand',
        'settings',
        'SETTINGS.toml',
      );
      final controller = await SettingsController.create(
        store: SettingsStore(settingsFilePath: settingsFilePath),
      );

      expect(await controller.updateAiSingleRoundToolCallLimit(55), isTrue);

      final reloadedController = await SettingsController.create(
        store: SettingsStore(settingsFilePath: settingsFilePath),
      );

      expect(reloadedController.aiSingleRoundToolCallLimit, 55);
    },
  );

  test('SettingsController persists the sequential tool round limit', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_settings_tool_round_limit_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final settingsFilePath = p.join(
      tempDirectory.path,
      '.openhand',
      'settings',
      'SETTINGS.toml',
    );
    final controller = await SettingsController.create(
      store: SettingsStore(settingsFilePath: settingsFilePath),
    );

    expect(await controller.updateAiSequentialToolRoundLimit(18), isTrue);

    final reloadedController = await SettingsController.create(
      store: SettingsStore(settingsFilePath: settingsFilePath),
    );

    expect(reloadedController.aiSequentialToolRoundLimit, 18);
  });
}
