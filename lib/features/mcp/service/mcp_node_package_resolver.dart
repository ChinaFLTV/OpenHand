import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/node_package_manifest.dart';
import '../../../shared/util/version_compare.dart';

const Duration _mcpNodeResolverIdleTimeout = Duration(seconds: 3);
const Duration _mcpNodeResolverTotalTimeout = Duration(seconds: 8);
const int _mcpNodeResolverDirectoryEntryLimit = 256;
const int _mcpNodeResolverRuntimeCandidateLimit = 64;
final RegExp _mcpNodePackageVersionSuffixPattern = RegExp(r'@[^/]*$');
final RegExp _mcpNodePackageNamePattern = RegExp(
  r'^(?:@[A-Za-z0-9._~-]+/)?[A-Za-z0-9._~-]+$',
);

final class McpNodePackageResolution {
  const McpNodePackageResolution({
    required this.nodeBin,
    required this.entryScript,
  });

  final String nodeBin;
  final String entryScript;
}

/// Resolves an already-installed npm package without invoking a package
/// manager. Runtime directory scans, metadata probes, and manifest reads share
/// one total budget so a large or stalled version-manager tree cannot block MCP
/// startup indefinitely.
Future<McpNodePackageResolution?> resolveInstalledMcpNodePackage(
  String packageName, {
  String? homeDirectory,
  String? nvmDirectory,
  Duration totalTimeout = _mcpNodeResolverTotalTimeout,
  int maxRuntimeCandidates = _mcpNodeResolverRuntimeCandidateLimit,
}) async {
  if (totalTimeout <= Duration.zero) {
    throw ArgumentError.value(
      totalTimeout,
      'totalTimeout',
      'Must be positive.',
    );
  }
  if (maxRuntimeCandidates < 1) {
    throw ArgumentError.value(
      maxRuntimeCandidates,
      'maxRuntimeCandidates',
      'Must be positive.',
    );
  }
  final cleanName = normalizeMcpNodePackageName(packageName);
  if (cleanName == null) return null;
  final home = homeDirectory?.trim();
  final budget = _McpNodeResolverBudget(totalTimeout);

  try {
    if (home != null && home.isNotEmpty) {
      final explicitNvmRoot = nvmDirectory?.trim();
      final environmentNvmRoot = Platform.environment['NVM_DIR']?.trim();
      final nvmRoot = explicitNvmRoot != null && explicitNvmRoot.isNotEmpty
          ? explicitNvmRoot
          : environmentNvmRoot;
      final nvmDir = nvmRoot == null || nvmRoot.isEmpty
          ? p.join(home, '.nvm')
          : nvmRoot;
      final nvmVersions = await _runtimeDirectories(
        Directory(p.join(nvmDir, 'versions', 'node')),
        budget,
      );
      nvmVersions.sort(
        (a, b) =>
            compareSemanticVersions(p.basename(b.path), p.basename(a.path)),
      );
      for (final version in nvmVersions.take(maxRuntimeCandidates)) {
        final resolution = await _resolvePackageCandidate(
          nodeBin: p.join(version.path, 'bin', 'node'),
          packageDirectory: p.join(
            version.path,
            'lib',
            'node_modules',
            cleanName,
          ),
          budget: budget,
        );
        if (resolution != null) return resolution;
      }

      final voltaPackage = p.join(
        home,
        '.volta',
        'tools',
        'image',
        'packages',
        cleanName,
      );
      final voltaResolution = await _resolvePackageCandidate(
        nodeBin: p.join(home, '.volta', 'bin', 'node'),
        packageDirectory: voltaPackage,
        budget: budget,
      );
      if (voltaResolution != null) return voltaResolution;

      final fnmRoots = <String>{
        p.join(home, 'Library', 'Application Support', 'fnm', 'node-versions'),
        p.join(home, '.local', 'share', 'fnm', 'node-versions'),
      };
      for (final fnmRoot in fnmRoots) {
        final fnmVersions = await _runtimeDirectories(
          Directory(fnmRoot),
          budget,
        );
        fnmVersions.sort(
          (a, b) =>
              compareSemanticVersions(p.basename(b.path), p.basename(a.path)),
        );
        for (final version in fnmVersions.take(maxRuntimeCandidates)) {
          final installation = p.join(version.path, 'installation');
          final resolution = await _resolvePackageCandidate(
            nodeBin: p.join(installation, 'bin', 'node'),
            packageDirectory: p.join(
              installation,
              'lib',
              'node_modules',
              cleanName,
            ),
            budget: budget,
          );
          if (resolution != null) return resolution;
        }
      }
    }

    const systemRoots = <String>[
      '/opt/homebrew/lib/node_modules',
      '/usr/local/lib/node_modules',
      '/usr/lib/node_modules',
    ];
    const systemNodes = <String>[
      '/opt/homebrew/bin/node',
      '/usr/local/bin/node',
      '/usr/bin/node',
    ];
    for (final packageRoot in systemRoots) {
      for (final nodeBin in systemNodes) {
        final resolution = await _resolvePackageCandidate(
          nodeBin: nodeBin,
          packageDirectory: p.join(packageRoot, cleanName),
          budget: budget,
        );
        if (resolution != null) return resolution;
      }
    }
    return null;
  } on TimeoutException {
    return null;
  }
}

/// Returns existing absolute login-shell candidates in stable priority order.
Future<List<String>> existingMcpLoginShells() async {
  final preferred = Platform.environment['SHELL']?.trim();
  final candidates = <String>{
    if (preferred != null && preferred.isNotEmpty && p.isAbsolute(preferred))
      preferred,
    '/bin/zsh',
    '/bin/bash',
  };
  final existing = <String>[];
  for (final candidate in candidates) {
    if (await _isEntityType(
      candidate,
      FileSystemEntityType.file,
      _mcpNodeResolverIdleTimeout,
    )) {
      existing.add(candidate);
    }
  }
  return existing;
}

Future<String> resolveMcpLoginShell() async {
  final shells = await existingMcpLoginShells();
  return shells.isEmpty ? '/bin/bash' : shells.first;
}

String quoteMcpShellToken(String value) {
  return "'${value.replaceAll("'", "'\\''")}'";
}

String? normalizeMcpNodePackageName(String packageName) {
  final name = packageName.replaceAll(_mcpNodePackageVersionSuffixPattern, '');
  if (name.isEmpty || !_mcpNodePackageNamePattern.hasMatch(name)) return null;
  final segments = name.split('/');
  if (segments.isNotEmpty && segments.first.startsWith('@')) {
    segments[0] = segments.first.substring(1);
  }
  if (segments.any((segment) => segment == '.' || segment == '..')) {
    return null;
  }
  return name;
}

Future<McpNodePackageResolution?> resolveMcpNodePackageCandidate({
  required String nodeBin,
  required String packageDirectory,
  Duration totalTimeout = _mcpNodeResolverTotalTimeout,
}) {
  if (totalTimeout <= Duration.zero) {
    throw ArgumentError.value(
      totalTimeout,
      'totalTimeout',
      'Must be positive.',
    );
  }
  return _resolvePackageCandidate(
    nodeBin: nodeBin,
    packageDirectory: packageDirectory,
    budget: _McpNodeResolverBudget(totalTimeout),
  );
}

Future<List<Directory>> _runtimeDirectories(
  Directory root,
  _McpNodeResolverBudget budget,
) async {
  if (!await _isEntityType(
    root.path,
    FileSystemEntityType.directory,
    budget.nextTimeout(),
  )) {
    return const <Directory>[];
  }
  try {
    final listing = await listDirectoryBounded(
      root,
      maxEntries: _mcpNodeResolverDirectoryEntryLimit,
      idleTimeout: budget.nextTimeout(),
      totalTimeout: budget.remaining,
    );
    return listing.entries.whereType<Directory>().toList(growable: false);
  } on FileSystemException {
    return const <Directory>[];
  } on TimeoutException {
    return const <Directory>[];
  }
}

Future<McpNodePackageResolution?> _resolvePackageCandidate({
  required String nodeBin,
  required String packageDirectory,
  required _McpNodeResolverBudget budget,
}) async {
  if (!await _isEntityType(
        nodeBin,
        FileSystemEntityType.file,
        budget.nextTimeout(),
      ) ||
      !await _isEntityType(
        packageDirectory,
        FileSystemEntityType.directory,
        budget.nextTimeout(),
      )) {
    return null;
  }
  final entry = await resolveNodePackageBinEntry(
    packageDirectory,
    idleTimeout: budget.nextTimeout(),
    totalTimeout: budget.remaining,
  );
  if (entry == null) return null;
  return McpNodePackageResolution(nodeBin: nodeBin, entryScript: entry);
}

Future<bool> _isEntityType(
  String path,
  FileSystemEntityType expected,
  Duration timeout,
) async {
  try {
    return await FileSystemEntity.type(path).timeout(timeout) == expected;
  } on FileSystemException {
    return false;
  } on TimeoutException {
    return false;
  } on ArgumentError {
    return false;
  }
}

final class _McpNodeResolverBudget {
  _McpNodeResolverBudget(this.totalTimeout) : _stopwatch = Stopwatch()..start();

  final Duration totalTimeout;
  final Stopwatch _stopwatch;

  Duration get remaining {
    final microseconds =
        totalTimeout.inMicroseconds - _stopwatch.elapsedMicroseconds;
    if (microseconds <= 0) {
      throw TimeoutException(
        'MCP Node package resolution exceeded its time limit.',
        totalTimeout,
      );
    }
    return Duration(microseconds: microseconds);
  }

  Duration nextTimeout() {
    final available = remaining;
    return available < _mcpNodeResolverIdleTimeout
        ? available
        : _mcpNodeResolverIdleTimeout;
  }
}
