import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openhand/app/state/settings_store.dart';

void main() {
  test(
    'SettingsStore preserves sanitized settings when rewriting them fails during load',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_settings_store_sanitize_save_failure_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final settingsFilePath = p.join(
        tempDirectory.path,
        '.openhand',
        'settings',
        'SETTINGS.toml',
      );
      final targetFile = File(settingsFilePath);
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsString('''
version = 1
theme_mode = "dark"
theme_preset = "sunrise"
language = "zh-CN"
skills_storage_path = "/tmp/custom-skills"
mcp_enabled = true
mcp_servers_file_path = "/tmp/custom-mcp.json"
memory_enabled = "oops"
user_memory_file = "/tmp/custom-memory.json"
ai_message_compression_threshold_chars = 5000
ai_single_round_tool_call_limit = 20
ai_write_command_confirmation_enabled = true
ai_allow_command_rules = "[]"
ai_deny_command_rules = "[]"
selected_ai_model_id = ""
''', flush: true);

      final store = _FailingSanitizedSettingsStore(
        settingsFilePath: settingsFilePath,
      );
      final result = await store.load();

      expect(result.snapshot.skillsStoragePath, '/tmp/custom-skills');
      expect(result.snapshot.memoryEnabled, isTrue);
      expect(result.issue?.kind, SettingsPersistenceIssueKind.saveFailed);
      expect(result.issue?.filePath, settingsFilePath);
      expect(result.issue?.detail, contains('Injected settings save failure'));
      expect(await targetFile.exists(), isTrue);
      expect(
        await targetFile.readAsString(),
        contains('memory_enabled = "oops"'),
      );
      expect(
        Directory(targetFile.parent.path).listSync().whereType<File>().where(
          (file) => p.basename(file.path).startsWith('SETTINGS.invalid-'),
        ),
        isEmpty,
      );
    },
  );
}

class _FailingSanitizedSettingsStore extends SettingsStore {
  _FailingSanitizedSettingsStore({required super.settingsFilePath});

  @override
  Future<void> save(snapshot) async {
    throw const FileSystemException('Injected settings save failure');
  }
}
