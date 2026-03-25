import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/service/ai_git_snapshot_service.dart';

void main() {
  test(
    'AiGitSnapshotService returns a non-git snapshot when git is unavailable',
    () async {
      final service = AiGitSnapshotService(
        processRunner:
            (
              String executable,
              List<String> arguments, {
              required String workingDirectory,
            }) async {
              return ProcessResult(0, 128, '', 'fatal: not a git repository');
            },
        clock: () => DateTime.utc(2026, 3, 25, 0, 0, 0),
      );

      final snapshot = await service.loadSnapshot(
        workingDirectory: '/workspace/openhand',
      );

      expect(snapshot.workingDirectory, '/workspace/openhand');
      expect(snapshot.isGitRepository, isFalse);
      expect(snapshot.currentBranch, isEmpty);
      expect(snapshot.recentCommits, isEmpty);
    },
  );

  test(
    'AiGitSnapshotService loads branch, status, and recent commits for a git repository',
    () async {
      final recordedCommands = <String>[];
      final service = AiGitSnapshotService(
        processRunner:
            (
              String executable,
              List<String> arguments, {
              required String workingDirectory,
            }) async {
              final commandKey = arguments.join(' ');
              recordedCommands.add(commandKey);
              switch (commandKey) {
                case 'rev-parse --is-inside-work-tree':
                  return ProcessResult(0, 0, 'true\n', '');
                case 'rev-parse --show-toplevel':
                  return ProcessResult(0, 0, '/workspace/openhand\n', '');
                case 'rev-parse --abbrev-ref HEAD':
                  return ProcessResult(0, 0, 'feature/runtime-snapshot\n', '');
                case 'symbolic-ref --quiet --short refs/remotes/origin/HEAD':
                  return ProcessResult(0, 0, 'origin/main\n', '');
                case 'status --short --branch':
                  return ProcessResult(
                    0,
                    0,
                    '## feature/runtime-snapshot\n M lib/main.dart\n',
                    '',
                  );
                case 'log --oneline -5':
                  return ProcessResult(
                    0,
                    0,
                    'abc1234 add runtime snapshot\n'
                        'def5678 tighten tool contracts\n',
                    '',
                  );
              }
              return ProcessResult(0, 0, '', '');
            },
        clock: () => DateTime.utc(2026, 3, 25, 0, 5, 0),
      );

      final snapshot = await service.loadSnapshot(
        workingDirectory: '/workspace/openhand',
      );

      expect(snapshot.isGitRepository, isTrue);
      expect(snapshot.repositoryRootPath, '/workspace/openhand');
      expect(snapshot.currentBranch, 'feature/runtime-snapshot');
      expect(snapshot.mainBranch, 'main');
      expect(snapshot.statusSnapshot, contains('M lib/main.dart'));
      expect(snapshot.recentCommits, <String>[
        'abc1234 add runtime snapshot',
        'def5678 tighten tool contracts',
      ]);
      expect(
        recordedCommands,
        contains('symbolic-ref --quiet --short refs/remotes/origin/HEAD'),
      );
    },
  );

  test(
    'AiGitSnapshotService reuses a fresh cached snapshot for repeated requests',
    () async {
      final recordedCommands = <String>[];
      var now = DateTime.utc(2026, 3, 25, 0, 10, 0);
      final service = AiGitSnapshotService(
        processRunner:
            (
              String executable,
              List<String> arguments, {
              required String workingDirectory,
            }) async {
              final commandKey = arguments.join(' ');
              recordedCommands.add(commandKey);
              switch (commandKey) {
                case 'rev-parse --is-inside-work-tree':
                  return ProcessResult(0, 0, 'true\n', '');
                case 'rev-parse --show-toplevel':
                  return ProcessResult(0, 0, '/workspace/openhand\n', '');
                case 'rev-parse --abbrev-ref HEAD':
                  return ProcessResult(0, 0, 'main\n', '');
                case 'symbolic-ref --quiet --short refs/remotes/origin/HEAD':
                  return ProcessResult(0, 0, 'origin/main\n', '');
                case 'status --short --branch':
                  return ProcessResult(0, 0, '## main\n', '');
                case 'log --oneline -5':
                  return ProcessResult(0, 0, 'abc1234 init\n', '');
              }
              return ProcessResult(0, 0, '', '');
            },
        clock: () => now,
        cacheTtl: const Duration(seconds: 5),
      );

      final firstSnapshot = await service.loadSnapshot(
        workingDirectory: '/workspace/openhand',
      );
      now = now.add(const Duration(seconds: 1));
      final secondSnapshot = await service.loadSnapshot(
        workingDirectory: '/workspace/openhand',
      );

      expect(firstSnapshot.currentBranch, 'main');
      expect(secondSnapshot.currentBranch, 'main');
      expect(recordedCommands, hasLength(6));
    },
  );

  test(
    'AiGitSnapshotService treats timed out git commands as a non-git snapshot',
    () async {
      final service = AiGitSnapshotService(
        processRunner:
            (
              String executable,
              List<String> arguments, {
              required String workingDirectory,
            }) async {
              await Future<void>.delayed(const Duration(milliseconds: 40));
              return ProcessResult(0, 0, 'true\n', '');
            },
        clock: () => DateTime.utc(2026, 3, 25, 0, 20, 0),
        commandTimeout: const Duration(milliseconds: 5),
      );

      final snapshot = await service.loadSnapshot(
        workingDirectory: '/workspace/openhand',
      );

      expect(snapshot.isGitRepository, isFalse);
      expect(snapshot.currentBranch, isEmpty);
      expect(snapshot.statusSnapshot, isEmpty);
    },
  );
}
