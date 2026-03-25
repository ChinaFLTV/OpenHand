import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/ai_session_runtime_context.dart';

typedef AiProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

class AiGitSnapshotService {
  AiGitSnapshotService({
    AiProcessRunner? processRunner,
    DateTime Function()? clock,
    Duration cacheTtl = const Duration(seconds: 3),
    Duration commandTimeout = const Duration(seconds: 2),
  }) : _processRunner = processRunner,
       _clock = clock ?? DateTime.now,
       _cacheTtl = cacheTtl,
       _commandTimeout = commandTimeout;

  final AiProcessRunner? _processRunner;
  final DateTime Function() _clock;
  final Duration _cacheTtl;
  final Duration _commandTimeout;
  final Map<String, _CachedGitSnapshot> _snapshotCache =
      <String, _CachedGitSnapshot>{};
  final Map<String, Future<AiRepositorySnapshot>> _pendingLoads =
      <String, Future<AiRepositorySnapshot>>{};

  Future<AiRepositorySnapshot> loadSnapshot({
    required String workingDirectory,
  }) async {
    final normalizedDirectory = p.normalize(workingDirectory.trim());
    final cachedSnapshot = _readFreshCachedSnapshot(normalizedDirectory);
    if (cachedSnapshot != null) {
      return cachedSnapshot;
    }
    final pendingLoad = _pendingLoads[normalizedDirectory];
    if (pendingLoad != null) {
      return pendingLoad;
    }
    final loadFuture = _loadSnapshotUncached(normalizedDirectory);
    _pendingLoads[normalizedDirectory] = loadFuture;
    return loadFuture.whenComplete(() {
      if (identical(_pendingLoads[normalizedDirectory], loadFuture)) {
        _pendingLoads.remove(normalizedDirectory);
      }
    });
  }

  AiRepositorySnapshot? _readFreshCachedSnapshot(String workingDirectory) {
    if (_cacheTtl <= Duration.zero) {
      return null;
    }
    final cached = _snapshotCache[workingDirectory];
    if (cached == null) {
      return null;
    }
    final age = _clock().toUtc().difference(cached.cachedAt);
    if (age > _cacheTtl) {
      _snapshotCache.remove(workingDirectory);
      return null;
    }
    return cached.snapshot;
  }

  Future<AiRepositorySnapshot> _loadSnapshotUncached(
    String normalizedDirectory,
  ) async {
    final capturedAt = _clock().toUtc().toIso8601String();
    final isGitRepository = await _isGitRepository(normalizedDirectory);
    late final AiRepositorySnapshot snapshot;
    if (!isGitRepository) {
      snapshot = AiRepositorySnapshot(
        workingDirectory: normalizedDirectory,
        isGitRepository: false,
        capturedAtIso8601: capturedAt,
      );
      return _cacheSnapshot(snapshot);
    }

    final repositoryRootPath = await _readGitText(
      normalizedDirectory,
      const <String>['rev-parse', '--show-toplevel'],
    );
    final currentBranch = await _readGitText(
      normalizedDirectory,
      const <String>['rev-parse', '--abbrev-ref', 'HEAD'],
    );
    final mainBranch = await _resolveMainBranch(
      normalizedDirectory,
      fallbackBranch: currentBranch,
    );
    final statusSnapshot = await _readGitText(
      normalizedDirectory,
      const <String>['status', '--short', '--branch'],
    );
    final recentCommitLines = await _readGitText(
      normalizedDirectory,
      const <String>['log', '--oneline', '-5'],
    );
    snapshot = AiRepositorySnapshot(
      workingDirectory: normalizedDirectory,
      isGitRepository: true,
      repositoryRootPath: repositoryRootPath,
      currentBranch: currentBranch,
      mainBranch: mainBranch,
      statusSnapshot: statusSnapshot,
      recentCommits: recentCommitLines
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      capturedAtIso8601: capturedAt,
    );
    return _cacheSnapshot(snapshot);
  }

  AiRepositorySnapshot _cacheSnapshot(AiRepositorySnapshot snapshot) {
    if (_cacheTtl > Duration.zero) {
      _snapshotCache[snapshot.workingDirectory] = _CachedGitSnapshot(
        snapshot: snapshot,
        cachedAt: _clock().toUtc(),
      );
    }
    return snapshot;
  }

  Future<bool> _isGitRepository(String workingDirectory) async {
    final result = await _runGit(workingDirectory, const <String>[
      'rev-parse',
      '--is-inside-work-tree',
    ]);
    return result.exitCode == 0 && result.stdout.trim() == 'true';
  }

  Future<String> _resolveMainBranch(
    String workingDirectory, {
    required String fallbackBranch,
  }) async {
    final remoteHead = await _readGitText(workingDirectory, const <String>[
      'symbolic-ref',
      '--quiet',
      '--short',
      'refs/remotes/origin/HEAD',
    ]);
    if (remoteHead.isNotEmpty) {
      final segments = remoteHead.split('/');
      return segments.isEmpty ? remoteHead : segments.last.trim();
    }
    if (await _hasLocalBranch(workingDirectory, 'main')) {
      return 'main';
    }
    if (await _hasLocalBranch(workingDirectory, 'master')) {
      return 'master';
    }
    return fallbackBranch;
  }

  Future<bool> _hasLocalBranch(String workingDirectory, String branch) async {
    final result = await _runGit(workingDirectory, <String>[
      'show-ref',
      '--verify',
      '--quiet',
      'refs/heads/$branch',
    ]);
    return result.exitCode == 0;
  }

  Future<String> _readGitText(
    String workingDirectory,
    List<String> arguments,
  ) async {
    final result = await _runGit(workingDirectory, arguments);
    if (result.exitCode != 0) {
      return '';
    }
    return result.stdout.trim();
  }

  Future<ProcessResult> _runGit(
    String workingDirectory,
    List<String> arguments,
  ) async {
    try {
      final processRunner = _processRunner;
      if (processRunner != null) {
        return await processRunner(
          'git',
          arguments,
          workingDirectory: workingDirectory,
        ).timeout(
          _commandTimeout,
          onTimeout: () => ProcessResult(
            0,
            124,
            '',
            'Git command timed out after ${_commandTimeout.inMilliseconds} ms.',
          ),
        );
      }
      return await _runGitProcessWithTimeout(
        workingDirectory,
        arguments,
        _commandTimeout,
      );
    } on ProcessException catch (error) {
      return ProcessResult(0, 127, '', error.message);
    }
  }

  static Future<ProcessResult> _runGitProcessWithTimeout(
    String workingDirectory,
    List<String> arguments,
    Duration timeout,
  ) async {
    final process = await Process.start(
      'git',
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      return ProcessResult(
        process.pid,
        exitCode,
        await stdoutFuture,
        await stderrFuture,
      );
    } on TimeoutException {
      process.kill();
      final stdout = await stdoutFuture.catchError((Object _) => '');
      final stderr = await stderrFuture.catchError((Object _) => '');
      final timeoutMessage =
          'Git command timed out after ${timeout.inMilliseconds} ms.';
      return ProcessResult(
        process.pid,
        124,
        stdout,
        stderr.isEmpty ? timeoutMessage : '$stderr\n$timeoutMessage',
      );
    }
  }
}

class _CachedGitSnapshot {
  const _CachedGitSnapshot({required this.snapshot, required this.cachedAt});

  final AiRepositorySnapshot snapshot;
  final DateTime cachedAt;
}
