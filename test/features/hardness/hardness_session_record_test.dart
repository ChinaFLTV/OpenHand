import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/hardness/model/hardness_role_config.dart';
import 'package:openhand/features/hardness/model/hardness_session_record.dart';
import 'package:openhand/features/hardness/service/hardness_orchestrator.dart';

void main() {
  group('HardnessRoleConfig.fromJson', () {
    test('tolerates loosely typed optional fields', () {
      final config = HardnessRoleConfig.fromJson(<String, Object?>{
        'cli_name': 'Claude Code',
        'model_id': 42,
        'execution_mode': 'url',
        'ai_model_config_id': 99,
        'url_mode_model_id': false,
      });

      expect(config.cliName, 'Claude Code');
      expect(config.modelId, '42');
      expect(config.executionMode, HardnessExecutionMode.url);
      expect(config.aiModelConfigId, '99');
      expect(config.urlModeModelId, 'false');
    });
  });

  group('HardnessSessionRecord.fromJson', () {
    test('recovers loose persisted records without throwing', () {
      final createdAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final updatedAt = DateTime.utc(2026, 1, 3, 4, 5, 6);

      final record = HardnessSessionRecord.fromJson(<String, Object?>{
        'id': 99,
        'title': '恢复测试',
        'config': <Object?, Object?>{
          'task': '重构 hardness',
          'working_directory': '/tmp/work',
          'persistence_directory': '/tmp/persist',
          'profiler': _roleJson('profiler'),
          'reader': _roleJson('reader'),
          'planner': _roleJson('planner'),
          'implementer': _roleJson('implementer'),
          'reviewer': _roleJson('reviewer'),
        },
        'status': 'running',
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt,
        'phase_logs': <Object?>[
          <Object?, Object?>{
            'phase': 'meta_collection',
            'status': 'completed',
            'lines': <Object?>['start', '', null, 7],
            'exit_code': '0',
            'saved_log_path': 123,
            'changed_files': <Object?>[
              <Object?, Object?>{
                'relative_path': 'lib/a.dart',
                'absolute_path': '/tmp/work/lib/a.dart',
                'change_type': 'added',
                'before_content': 12,
                'after_content': true,
              },
              'ignored',
            ],
            'review_verdict_fail': 'yes',
          },
          <Object?, Object?>{'phase': 'unknown'},
        ],
        'manual_phase_input_requested': 'on',
        'queued_manual_phase_input': 456,
        'queued_manual_phase_input_phase': 'planning',
      });

      expect(record.id, '99');
      expect(record.title, '恢复测试');
      expect(record.config.task, '重构 hardness');
      expect(record.config.profilerConfig.cliName, 'profiler');
      expect(record.status, HardnessOrchestratorStatus.running);
      expect(record.createdAt, createdAt);
      expect(record.updatedAt, updatedAt);
      expect(record.manualPhaseInputRequested, isTrue);
      expect(record.queuedManualPhaseInput, '456');
      expect(record.queuedManualPhaseInputPhaseValue, 'planning');
      expect(record.phaseLogs, hasLength(1));

      final log = record.phaseLogs.single;
      expect(log.lines, <String>['start', '', '', '7']);
      expect(log.exitCode, 0);
      expect(log.savedLogPath, '123');
      expect(log.reviewVerdictFail, isTrue);
      expect(log.changedFiles, hasLength(1));

      final changedFile = log.parsedChangedFiles.single;
      expect(changedFile.changeType, HardnessFileChangeType.added);
      expect(changedFile.beforeContent, '12');
      expect(changedFile.afterContent, 'true');
    });

    test('keeps legacy manual review input compatibility', () {
      final record = HardnessSessionRecord.fromJson(<String, Object?>{
        'config': <String, Object?>{},
        'manual_review_input_requested': 1,
        'queued_manual_review_input': '继续执行',
      });

      expect(record.manualPhaseInputRequested, isTrue);
      expect(record.queuedManualPhaseInput, '继续执行');
      expect(record.queuedManualPhaseInputPhaseValue, 'reviewing');
    });
  });

  group('HardnessPhaseLogSnapshot.fromJson', () {
    test('ignores non-integral exit codes', () {
      final snapshot = HardnessPhaseLogSnapshot.fromJson(<String, Object?>{
        'phase': 'reading',
        'exit_code': '2.5',
        'review_verdict_fail': 0,
        'changed_files': <String, Object?>{'not': 'a list'},
      });

      expect(snapshot, isNotNull);
      expect(snapshot!.exitCode, isNull);
      expect(snapshot.reviewVerdictFail, isFalse);
      expect(snapshot.changedFiles, isEmpty);
    });
  });
}

Map<Object?, Object?> _roleJson(String name) {
  return <Object?, Object?>{
    'cli_name': name,
    'model_id': '$name-model',
    'execution_mode': 'cli',
  };
}
