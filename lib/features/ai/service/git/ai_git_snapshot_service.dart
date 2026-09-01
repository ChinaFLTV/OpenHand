import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';
import '../../model/ai_session_runtime_context.dart';

typedef AiProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

class AiGitSnapshotService {
  AiGitSnapshotService({
    this._processRunner,
    DateTime Function()? clock,
    this._cacheTtl = const Duration(seconds: 3),
    this._commandTimeout = const Duration(seconds: 2),
    int cacheMaxEntries = 64,
  }) : _clock = clock ?? DateTime.now,
       _snapshotCache = LifecycleLruCache<_CachedGitSnapshot>(
         maxEntries: cacheMaxEntries,
       );

  final AiProcessRunner? _processRunner;
  final DateTime Function() _clock;
  final Duration _cacheTtl;
  final Duration _commandTimeout;
  final LifecycleLruCache<_CachedGitSnapshot> _snapshotCache;
  final OpenHandKeyedSingleFlight<String, AiRepositorySnapshot> _loadFlights =
      OpenHandKeyedSingleFlight<String, AiRepositorySnapshot>();

  Future<AiRepositorySnapshot> loadSnapshot({
    required String workingDirectory,
  }) async {
    final normalizedDirectory = p.normalize(workingDirectory.trim());
    final cachedSnapshot = _readFreshCachedSnapshot(normalizedDirectory);
    if (cachedSnapshot != null) {
      return cachedSnapshot;
    }
    return _loadFlights.run(
      normalizedDirectory,
      () => _loadSnapshotUncached(normalizedDirectory),
    );
  }

  AiRepositorySnapshot? _readFreshCachedSnapshot(String workingDirectory) {
    if (_cacheTtl <= Duration.zero) {
      return null;
    }
    final cached = _snapshotCache.get(workingDirectory);
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

    final repositoryRootPathFuture = _readGitText(
      normalizedDirectory,
      const <String>['rev-parse', '--show-toplevel'],
    );
    final currentBranchFuture = _readGitText(
      normalizedDirectory,
      const <String>['rev-parse', '--abbrev-ref', 'HEAD'],
    );
    final remoteHeadFuture = _readGitText(normalizedDirectory, const <String>[
      'symbolic-ref',
      '--quiet',
      '--short',
      'refs/remotes/origin/HEAD',
    ]);
    final hasMainBranchFuture = _hasLocalBranch(normalizedDirectory, 'main');
    final hasMasterBranchFuture = _hasLocalBranch(
      normalizedDirectory,
      'master',
    );
    final statusSnapshotFuture = _readGitText(
      normalizedDirectory,
      const <String>['status', '--short', '--branch'],
    );
    final recentCommitLinesFuture = _readGitText(
      normalizedDirectory,
      const <String>['log', '--oneline', '-5'],
    );
    await Future.wait<Object>(<Future<Object>>[
      repositoryRootPathFuture,
      currentBranchFuture,
      remoteHeadFuture,
      hasMainBranchFuture,
      hasMasterBranchFuture,
      statusSnapshotFuture,
      recentCommitLinesFuture,
    ]);
    final currentBranch = await currentBranchFuture;
    final mainBranch = _resolveMainBranchFromSnapshot(
      remoteHead: await remoteHeadFuture,
      fallbackBranch: currentBranch,
      hasMainBranch: await hasMainBranchFuture,
      hasMasterBranch: await hasMasterBranchFuture,
    );
    final recentCommitLines = await recentCommitLinesFuture;
    snapshot = AiRepositorySnapshot(
      workingDirectory: normalizedDirectory,
      isGitRepository: true,
      repositoryRootPath: await repositoryRootPathFuture,
      currentBranch: currentBranch,
      mainBranch: mainBranch,
      statusSnapshot: await statusSnapshotFuture,
      recentCommits: splitTrimmedNonEmpty(recentCommitLines, separator: '\n'),
      capturedAtIso8601: capturedAt,
    );
    return _cacheSnapshot(snapshot);
  }

  AiRepositorySnapshot _cacheSnapshot(AiRepositorySnapshot snapshot) {
    if (_cacheTtl > Duration.zero) {
      _snapshotCache.put(
        snapshot.workingDirectory,
        _CachedGitSnapshot(snapshot: snapshot, cachedAt: _clock().toUtc()),
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

  String _resolveMainBranchFromSnapshot({
    required String remoteHead,
    required String fallbackBranch,
    required bool hasMainBranch,
    required bool hasMasterBranch,
  }) {
    if (remoteHead.isNotEmpty) {
      final segments = remoteHead.split('/');
      return segments.isEmpty ? remoteHead : segments.last.trim();
    }
    if (hasMainBranch) {
      return 'main';
    }
    if (hasMasterBranch) {
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
    final timeoutMessage =
        'Git command timed out after ${timeout.inMilliseconds} ms.';
    final result = await runProcessWithTimeout(
      'git',
      arguments,
      timeout: timeout,
      tag: 'ai_git_snapshot_service',
      workingDirectory: workingDirectory,
      environment: SystemProxyResolver.instance.resolveSubprocessEnvironment(),
      timeoutResultBuilder: (pid, stdout, stderr) => ProcessResult(
        pid,
        124,
        stdout,
        stderr.isEmpty ? timeoutMessage : '$stderr\n$timeoutMessage',
      ),
    );
    return result ??
        ProcessResult(0, 127, '', 'Unable to start the Git command.');
  }
}

class _CachedGitSnapshot {
  const _CachedGitSnapshot({required this.snapshot, required this.cachedAt});

  final AiRepositorySnapshot snapshot;
  final DateTime cachedAt;
}
