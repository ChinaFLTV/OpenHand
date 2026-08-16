import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../../shared/util/text_clip.dart';
import '../../model/ai_session_runtime_context.dart';

class AiWorkspaceInstructionService {
  AiWorkspaceInstructionService({
    DateTime Function()? clock,
    Duration cacheTtl = const Duration(seconds: 3),
  }) : _clock = clock ?? DateTime.now,
       _cacheTtl = cacheTtl;

  int maxDocumentCharacters = 16000;
  static const int _maxDocumentBytes = 256 * kBytesPerKiB;
  static const int _maxRuleFilesPerDirectory = 128;
  static const int _maxRuleDirectoryScanEntries = 512;
  static const int _maxDocuments = 256;
  static const int _maxCacheEntries = 64;
  static const int _maxCachedCharacters = 2 * kBytesPerMiB;
  static const List<String> _workspaceInstructionFiles = <String>[
    'AGENTS.md',
    'CLAUDE.md',
  ];
  final DateTime Function() _clock;
  final Duration _cacheTtl;
  final LifecycleLruCache<_CachedWorkspaceInstructions> _cache =
      LifecycleLruCache<_CachedWorkspaceInstructions>(
        maxEntries: _maxCacheEntries,
        maxCost: _maxCachedCharacters,
        costOf: (entry) => entry.documents.fold<int>(
          0,
          (total, document) => total + document.content.length,
        ),
      );
  final OpenHandKeyedSingleFlight<String, List<AiWorkspaceInstructionDocument>>
  _loadFlights =
      OpenHandKeyedSingleFlight<String, List<AiWorkspaceInstructionDocument>>();

  Future<List<AiWorkspaceInstructionDocument>> loadDocuments({
    required String startDirectory,
    String? homeDirectory,
  }) async {
    final startValue = nullIfBlank(startDirectory);
    if (startValue == null) {
      return const <AiWorkspaceInstructionDocument>[];
    }
    final normalizedStart = p.normalize(startValue);
    if (await probeFileSystemEntityType(normalizedStart, followLinks: true) !=
        FileSystemEntityType.directory) {
      return const <AiWorkspaceInstructionDocument>[];
    }
    final homeValue = nullIfBlank(homeDirectory);
    final normalizedHome = homeValue == null ? null : p.normalize(homeValue);
    final cacheKey = '$normalizedStart|${normalizedHome ?? ''}';
    final cachedDocuments = _readCachedDocuments(cacheKey);
    if (cachedDocuments != null) {
      return cachedDocuments;
    }
    return _loadFlights.run(
      cacheKey,
      () => _loadDocumentsUncached(
        normalizedStart: normalizedStart,
        normalizedHome: normalizedHome,
        cacheKey: cacheKey,
      ),
    );
  }

  Future<List<AiWorkspaceInstructionDocument>> _loadDocumentsUncached({
    required String normalizedStart,
    required String? normalizedHome,
    required String cacheKey,
  }) async {
    final seenPaths = <String>{};
    final documents = <AiWorkspaceInstructionDocument>[];

    Future<void> addDocument(String filePath) async {
      if (documents.length >= _maxDocuments) return;
      final normalizedPath = p.normalize(filePath);
      if (!seenPaths.add(normalizedPath)) {
        return;
      }
      final file = File(normalizedPath);
      try {
        if (!await regularFileExistsBounded(file)) return;
        final content = await readBoundedFileString(
          file,
          maxBytes: _maxDocumentBytes,
        );
        final trimmedContent = content.trimRight();
        if (trimmedContent.isEmpty) {
          return;
        }
        documents.add(
          AiWorkspaceInstructionDocument(
            path: normalizedPath,
            name: p.basename(normalizedPath),
            content: _truncate(trimmedContent),
          ),
        );
      } on IOException {
        return;
      } on TimeoutException {
        return;
      } on FormatException {
        return;
      }
    }

    if (normalizedHome != null) {
      await addDocument(p.join(normalizedHome, '.claude', 'CLAUDE.md'));
      await _addRulesDocuments(
        rootDirectory: normalizedHome,
        addDocument: addDocument,
      );
    }

    for (final directory in ancestorDirectoriesFrom(
      normalizedStart,
      rootFirst: true,
    )) {
      for (final fileName in _workspaceInstructionFiles) {
        await addDocument(p.join(directory, fileName));
      }
      await _addRulesDocuments(
        rootDirectory: directory,
        addDocument: addDocument,
      );
    }
    return _cacheDocuments(cacheKey, documents);
  }

  List<AiWorkspaceInstructionDocument>? _readCachedDocuments(String cacheKey) {
    if (_cacheTtl <= Duration.zero) {
      return null;
    }
    final cached = _cache.get(cacheKey);
    if (cached == null) {
      return null;
    }
    final age = _clock().toUtc().difference(cached.cachedAt);
    if (age > _cacheTtl) {
      _cache.remove(cacheKey);
      return null;
    }
    return cached.documents;
  }

  List<AiWorkspaceInstructionDocument> _cacheDocuments(
    String cacheKey,
    List<AiWorkspaceInstructionDocument> documents,
  ) {
    final immutableDocuments =
        List<AiWorkspaceInstructionDocument>.unmodifiable(documents);
    if (_cacheTtl > Duration.zero) {
      _cache.put(
        cacheKey,
        _CachedWorkspaceInstructions(
          documents: immutableDocuments,
          cachedAt: _clock().toUtc(),
        ),
      );
    }
    return immutableDocuments;
  }

  Future<void> _addRulesDocuments({
    required String rootDirectory,
    required Future<void> Function(String filePath) addDocument,
  }) async {
    final rulesDirectory = Directory(p.join(rootDirectory, '.claude', 'rules'));
    if (await probeFileSystemEntityType(
          rulesDirectory.path,
          followLinks: true,
        ) !=
        FileSystemEntityType.directory) {
      return;
    }
    final ruleFiles = <String>[];
    final listing = await listDirectoryBounded(
      rulesDirectory,
      maxEntries: _maxRuleDirectoryScanEntries,
    );
    for (final item in listing.entries) {
      if (item is! File) continue;
      final normalizedPath = p.normalize(item.path);
      if (normalizedPath.toLowerCase().endsWith('.md')) {
        ruleFiles.add(normalizedPath);
        if (ruleFiles.length >= _maxRuleFilesPerDirectory) break;
      }
    }
    ruleFiles.sort();
    for (final filePath in ruleFiles) {
      await addDocument(filePath);
    }
  }

  String _truncate(String content) {
    return clipTextByCodeUnits(
      content,
      maxDocumentCharacters,
      suffix: '\n\n...[内容已截断]',
    );
  }
}

class _CachedWorkspaceInstructions {
  const _CachedWorkspaceInstructions({
    required this.documents,
    required this.cachedAt,
  });

  final List<AiWorkspaceInstructionDocument> documents;
  final DateTime cachedAt;
}
