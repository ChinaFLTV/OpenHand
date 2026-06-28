import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/web_message_platform_config.dart';

void main() {
  test('fromJson normalizes booleans, lists, and nested config maps', () {
    final config = WebMessagePlatformConfig.fromJson(<String, Object?>{
      'enabled': 'yes',
      'auto_start_on_launch': '0',
      'auto_reload_on_change': double.nan,
      'auth_enabled': 1,
      'telemetry_enabled': 'enabled',
      'logging_enabled': 'off',
      'ops_enabled': 'true',
      'allowed_template_ids': <Object?>[' a ', null, 'A', '', ' b '],
      'allowed_skill_names': 'skill-a, skill-b',
      'read_aloud_enabled': 'no',
      'translation_enabled': 'bad',
      'feedback_enabled': 0,
      'regeneration_enabled': '1',
      'session_management_enabled': 'false',
      'workspace_files_enabled': 'on',
      'workspace_file_write_enabled': 'yes',
      'health_check': <Object?, Object?>{
        'enabled': '1',
        'query_parameters': <Object?, Object?>{
          ' token ': ' abc ',
          'skip': null,
        },
        'follow_redirects': 'yes',
        'timeout_ms': double.infinity,
      },
      'log_config': <Object?, Object?>{
        'levels': <Object?>[' info ', null, 'INFO', '', ' error '],
        'lazy_read_page_size': '10',
      },
    });

    expect(config.enabled, isTrue);
    expect(config.autoStartOnLaunch, isFalse);
    expect(config.autoReloadOnChange, isTrue);
    expect(config.authEnabled, isTrue);
    expect(config.telemetryEnabled, isTrue);
    expect(config.loggingEnabled, isFalse);
    expect(config.opsEnabled, isTrue);
    expect(config.allowedTemplateIds, <String>['a', 'b']);
    expect(config.allowedSkillNames, <String>['skill-a', 'skill-b']);
    expect(config.readAloudEnabled, isFalse);
    expect(config.translationEnabled, isTrue);
    expect(config.feedbackEnabled, isFalse);
    expect(config.regenerationEnabled, isTrue);
    expect(config.sessionManagementEnabled, isFalse);
    expect(config.workspaceFilesEnabled, isTrue);
    expect(config.workspaceFileWriteEnabled, isTrue);
    expect(config.healthCheck.enabled, isTrue);
    expect(config.healthCheck.followRedirects, isTrue);
    expect(config.healthCheck.timeoutMs, 3000);
    expect(config.healthCheck.queryParameters, <String, String>{
      'token': 'abc',
    });
    expect(config.logConfig.levels, <String>['info', 'error']);
    expect(config.logConfig.lazyReadPageSize, 50);
  });

  test('fromJson falls back for malformed nested configs', () {
    final config = WebMessagePlatformConfig.fromJson(<String, Object?>{
      'health_check': 'bad',
      'log_config': <Object?>[],
    });

    expect(config.healthCheck.path, '/api/health');
    expect(config.logConfig.levels, <String>['info', 'warn', 'error', 'debug']);
  });
}
