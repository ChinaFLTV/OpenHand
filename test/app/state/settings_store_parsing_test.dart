import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late SettingsStore store;

  setUp(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_settings_store_parsing_test_',
    );
    await DatabaseService.initialize(
      databasePath: p.join(tempDir.path, 'openhand.db'),
      useNoIsolateFactory: true,
    );
    store = SettingsStore();
  });

  tearDown(() async {
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loads loose boolean and positive integer settings safely', () async {
    final db = DatabaseService.instance.database;
    await db.insert('app_settings', <String, Object?>{
      'key': 'app_settings_json',
      'value': jsonEncode(<String, Object?>{
        'version': '4',
        'mcp_enabled': 'false',
        'memory_enabled': 0,
        'editor_word_wrap': 'off',
        'ai_message_compression_threshold_chars': '24000',
        'ai_tool_result_compression_threshold_chars': '2048',
        'ai_tool_result_compression_enabled': 'no',
        'ai_micro_compression_enabled': 'disabled',
        'ai_input_cache_enabled': 'false',
        'ai_single_round_tool_call_limit': '9',
        'ai_sequential_tool_round_limit': '11',
        'ai_write_command_confirmation_enabled': '0',
        'ai_stream_throttle_enabled': 'disabled',
        'ai_stream_throttle_auto_mode': 'yes',
        'ai_stream_throttle_config_updated_at_ms': '123',
        'ai_auto_title_enabled': 'false',
        'ai_default_full_access_permission': 'true',
        'telemetry_debug_enabled': '1',
        'telemetry_capture_raw_payload': '0',
        'telemetry_capture_environment': 'enabled',
        'self_learning_enabled': 'disabled',
        'show_self_learning_messages': 'false',
        'cron_auto_cleanup_enabled': 'no',
        'reduce_motion': 'on',
        'ai_models': jsonEncode(<Object?>[
          <String, Object?>{
            'id': 'model-1',
            'name': 'Model One',
            'base_url': 'https://api.example.test/v1',
            'auth_scheme': 'bearer',
            'token': 'token',
            'model_id': 'gpt-test',
            'protocol_type': 'openai',
          },
          <String, Object?>{
            'id': 'invalid-url',
            'base_url': 'not-a-url',
            'auth_scheme': 'bearer',
            'token': 'token',
            'model_id': 'bad',
            'protocol_type': 'openai',
          },
        ]),
        'selected_ai_model_id': 'model-1',
        'recent_model_selections': jsonEncode(<Object?>[
          <String, Object?>{'config_id': 123, 'model_id': 456},
          <String, Object?>{'config_id': 'missing-model', 'model_id': ''},
        ]),
      }),
    });

    final loaded = await store.load();
    final snapshot = loaded.snapshot;

    expect(loaded.issue, isNull);
    expect(snapshot.mcpEnabled, isFalse);
    expect(snapshot.memoryEnabled, isFalse);
    expect(snapshot.editorWordWrap, isFalse);
    expect(snapshot.aiMessageCompressionThresholdChars, 24000);
    expect(snapshot.aiToolResultCompressionThresholdChars, 2048);
    expect(snapshot.aiToolResultCompressionEnabled, isFalse);
    expect(snapshot.aiMicroCompressionEnabled, isFalse);
    expect(snapshot.aiInputCacheEnabled, isFalse);
    expect(snapshot.aiSingleRoundToolCallLimit, 9);
    expect(snapshot.aiSequentialToolRoundLimit, 11);
    expect(snapshot.aiWriteCommandConfirmationEnabled, isFalse);
    expect(snapshot.aiStreamThrottleEnabled, isFalse);
    expect(snapshot.aiStreamThrottleAutoMode, isTrue);
    expect(snapshot.aiStreamThrottleConfigUpdatedAtMs, 123);
    expect(snapshot.aiAutoTitleEnabled, isFalse);
    expect(snapshot.aiDefaultFullAccessPermission, isTrue);
    expect(snapshot.telemetryDebugEnabled, isTrue);
    expect(snapshot.telemetryCaptureRawPayload, isFalse);
    expect(snapshot.telemetryCaptureEnvironment, isTrue);
    expect(snapshot.selfLearningEnabled, isFalse);
    expect(snapshot.showSelfLearningMessages, isFalse);
    expect(snapshot.cronAutoCleanupEnabled, isFalse);
    expect(snapshot.reduceMotion, isTrue);
    expect(snapshot.aiModels, hasLength(1));
    expect(snapshot.aiModels.single.id, 'model-1');
    expect(snapshot.selectedAiModelId, 'model-1');
    expect(snapshot.recentModelSelections, hasLength(1));
    expect(snapshot.recentModelSelections.single.configId, '123');
    expect(snapshot.recentModelSelections.single.modelId, '456');
  });
}
