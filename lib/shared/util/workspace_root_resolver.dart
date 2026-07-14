import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'path_safety.dart';

const List<String> standardWorkspaceRootMarkers = <String>[
  '.git',
  'pubspec.yaml',
  'package.json',
  'go.mod',
  'Cargo.toml',
  'pom.xml',
  'build.gradle',
  'build.gradle.kts',
  'mix.exs',
  'Gemfile',
  'build.sbt',
  'deno.json',
  'deno.jsonc',
  'gleam.toml',
  'build.zig',
  'Project.toml',
  'composer.json',
  'requirements.txt',
  'pyproject.toml',
  'setup.py',
];

final WorkspaceRootResolver standardWorkspaceRootResolver =
    WorkspaceRootResolver(markers: standardWorkspaceRootMarkers);

/// Resolves project roots without blocking the caller or retaining unbounded
/// path state. Concurrent requests for the same directory share one probe.
final class WorkspaceRootResolver {
  WorkspaceRootResolver({
    required Iterable<String> markers,
    this.maxMarkers = 64,
    this.maxCacheEntries = 512,
    this.maxPendingProbes = 32,
    this.maxAncestors = 128,
    this.idleTimeout = const Duration(milliseconds: 500),
    this.totalTimeout = const Duration(seconds: 5),
    this.cacheTtl = const Duration(seconds: 30),
  }) : markers = List<String>.unmodifiable(
         _normalizeMarkers(markers, maxMarkers: maxMarkers),
       ) {
    if (this.markers.isEmpty) {
      throw ArgumentError.value(markers, 'markers', 'Must not be empty.');
    }
    if (maxMarkers < 1 ||
        maxMarkers > _maxAllowedMarkers ||
        maxCacheEntries < 1 ||
        maxCacheEntries > _maxAllowedCacheEntries ||
        maxPendingProbes < 1 ||
        maxPendingProbes > _maxAllowedPendingProbes ||
        maxAncestors < 1 ||
        maxAncestors > kOpenHandMaxAncestorDirectoryDepth) {
      throw ArgumentError('Workspace root limits are outside safe bounds.');
    }
    if (idleTimeout <= Duration.zero ||
        totalTimeout <= Duration.zero ||
        cacheTtl <= Duration.zero ||
        idleTimeout > _maxAllowedIdleTimeout ||
        totalTimeout > _maxAllowedTotalTimeout ||
        cacheTtl > _maxAllowedCacheTtl) {
      throw ArgumentError('Workspace root timeouts are outside safe bounds.');
    }
  }

  static const int _maxAllowedMarkers = 64;
  static const int _maxAllowedCacheEntries = 4096;
  static const int _maxAllowedPendingProbes = 64;
  static const Duration _maxAllowedIdleTimeout = Duration(seconds: 10);
  static const Duration _maxAllowedTotalTimeout = Duration(seconds: 30);
  static const Duration _maxAllowedCacheTtl = Duration(hours: 1);

  final List<String> markers;
  final int maxMarkers;
  final int maxCacheEntries;
  final int maxPendingProbes;
  final int maxAncestors;
  final Duration idleTimeout;
  final Duration totalTimeout;
  final Duration cacheTtl;
  final LinkedHashMap<String, _WorkspaceRootCacheEntry> _cache =
      LinkedHashMap<String, _WorkspaceRootCacheEntry>();
  final Map<String, Future<String>> _pending = <String, Future<String>>{};
  final Stopwatch _clock = Stopwatch()..start();

  /// Returns a cached root for build-time formatting, or a lexical fallback
  /// while the asynchronous probe is still pending.
  String cachedOrFallback(String filePath) {
    final startDirectory = _startDirectory(filePath);
    if (startDirectory.isEmpty) return '';
    final cached = _readCache(startDirectory);
    if (cached != null) return cached;
    final ancestors = ancestorDirectoriesFrom(
      startDirectory,
      maxDepth: maxAncestors,
    );
    return ancestors.isEmpty ? startDirectory : ancestors.last;
  }

  Future<String> resolve(String filePath) {
    final startDirectory = _startDirectory(filePath);
    if (startDirectory.isEmpty) return Future<String>.value('');
    final cached = _readCache(startDirectory);
    if (cached != null) return Future<String>.value(cached);
    final active = _pending[startDirectory];
    if (active != null) return active;
    if (_pending.length >= maxPendingProbes) {
      return Future<String>.value(startDirectory);
    }

    late final Future<String> tracked;
    tracked = _probe(startDirectory).whenComplete(() {
      if (identical(_pending[startDirectory], tracked)) {
        _pending.remove(startDirectory);
      }
    });
    _pending[startDirectory] = tracked;
    return tracked;
  }

  void clear() => _cache.clear();

  Future<String> _probe(String startDirectory) async {
    final ancestors = ancestorDirectoriesFrom(
      startDirectory,
      maxDepth: maxAncestors,
    );
    final fallback = ancestors.isEmpty ? startDirectory : ancestors.last;
    final stopwatch = Stopwatch()..start();
    var root = fallback;
    var conclusive = true;

    search:
    for (final directory in ancestors) {
      for (final marker in markers) {
        final remaining = totalTimeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          conclusive = false;
          break search;
        }
        final timeout = remaining < idleTimeout ? remaining : idleTimeout;
        try {
          final type = await FileSystemEntity.type(
            p.join(directory, marker),
            followLinks: false,
          ).timeout(timeout);
          if (type != FileSystemEntityType.notFound) {
            root = directory;
            break search;
          }
        } on TimeoutException {
          conclusive = false;
        } on FileSystemException {
          conclusive = false;
        }
      }
    }

    if (conclusive) {
      _memoize(ancestors, root);
    }
    return root;
  }

  String? _readCache(String directory) {
    final entry = _cache.remove(directory);
    if (entry == null) return null;
    if (entry.expiresAtMicroseconds <= _clock.elapsedMicroseconds) {
      return null;
    }
    _cache[directory] = entry;
    return entry.root;
  }

  void _memoize(List<String> ancestors, String root) {
    final rootIndex = ancestors.indexOf(root);
    final entries = (rootIndex < 0 ? ancestors : ancestors.take(rootIndex + 1))
        .toList(growable: false);
    final expiresAt = _clock.elapsedMicroseconds + cacheTtl.inMicroseconds;
    for (final directory in entries.reversed) {
      _cache.remove(directory);
      _cache[directory] = _WorkspaceRootCacheEntry(
        root: root,
        expiresAtMicroseconds: expiresAt,
      );
    }
    while (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  static String _startDirectory(String filePath) {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) return '';
    return p.normalize(p.dirname(trimmed));
  }

  static List<String> _normalizeMarkers(
    Iterable<String> markers, {
    required int maxMarkers,
  }) {
    if (maxMarkers < 1 || maxMarkers > _maxAllowedMarkers) {
      throw ArgumentError.value(
        maxMarkers,
        'maxMarkers',
        'Must be between 1 and $_maxAllowedMarkers.',
      );
    }
    final normalized = <String>{};
    for (final rawMarker in markers) {
      final marker = rawMarker.trim();
      if (marker.isEmpty ||
          marker == '.' ||
          marker == '..' ||
          p.basename(marker) != marker) {
        throw ArgumentError.value(
          rawMarker,
          'markers',
          'Markers must be non-empty path basenames.',
        );
      }
      normalized.add(marker);
      if (normalized.length > maxMarkers) {
        throw ArgumentError.value(
          markers,
          'markers',
          'Must contain at most $maxMarkers unique markers.',
        );
      }
    }
    return normalized.toList(growable: false);
  }
}

final class _WorkspaceRootCacheEntry {
  const _WorkspaceRootCacheEntry({
    required this.root,
    required this.expiresAtMicroseconds,
  });

  final String root;
  final int expiresAtMicroseconds;
}
