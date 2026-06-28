import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';

void main() {
  test('parses repository snapshots from json text and loose values', () {
    final snapshot = AiRepositorySnapshot.fromJson(
      jsonEncode(<String, Object?>{
        'working_directory': ' /workspace ',
        'is_git_repository': 'enabled',
        'repository_root_path': '/workspace',
        'current_branch': ' main ',
        'main_branch': ' trunk ',
        'status_snapshot': ' clean ',
        'recent_commits': jsonEncode(<Object?>[' abc123 修复解析 ', '', 42]),
        'captured_at': ' 2026-06-28T08:00:00Z ',
      }),
    );

    expect(snapshot.workingDirectory, '/workspace');
    expect(snapshot.isGitRepository, isTrue);
    expect(snapshot.currentBranch, 'main');
    expect(snapshot.mainBranch, 'trunk');
    expect(snapshot.statusSnapshot, 'clean');
    expect(snapshot.recentCommits, <String>['abc123 修复解析', '42']);
    expect(snapshot.capturedAtIso8601, '2026-06-28T08:00:00Z');
  });

  test('falls back safely for malformed repository snapshots', () {
    final snapshot = AiRepositorySnapshot.fromJson('not-json');

    expect(snapshot.workingDirectory, isEmpty);
    expect(snapshot.isGitRepository, isFalse);
    expect(snapshot.recentCommits, isEmpty);
  });
}
