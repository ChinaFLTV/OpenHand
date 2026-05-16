import 'dart:io';

import 'package:path/path.dart' as p;

import '../../model/ai_session_runtime_context.dart';

class AiWorkspaceInstructionService {
  AiWorkspaceInstructionService({
    DateTime Function()? clock,
    Duration cacheTtl = const Duration(seconds: 3),
  }) : _clock = clock ?? DateTime.now,
       _cacheTtl = cacheTtl;

  int maxDocumentCharacters = 16000;
  static const List<String> _workspaceInstructionFiles = <String>[
    'AGENTS.md',
    'CLAUDE.md',
  ];
  final DateTime Function() _clock;
  final Duration _cacheTtl;
  final Map<String, _CachedWorkspaceInstructions> _cache =
      <String, _CachedWorkspaceInstructions>{};
  final Map<String, Future<List<AiWorkspaceInstructionDocument>>> _inFlight =
      <String, Future<List<AiWorkspaceInstructionDocument>>>{};

  Future<List<AiWorkspaceInstructionDocument>> loadDocuments({
    required String startDirectory,
    String? homeDirectory,
  }) async {
    final normalizedStart = p.normalize(startDirectory.trim());
    if (normalizedStart.isEmpty || !await Directory(normalizedStart).exists()) {
      return const <AiWorkspaceInstructionDocument>[];
    }
    final normalizedHome = (homeDirectory ?? '').trim().isEmpty
        ? null
        : p.normalize(homeDirectory!.trim());
    final cacheKey = '$normalizedStart|${normalizedHome ?? ''}';
    final cachedDocuments = _readCachedDocuments(cacheKey);
    if (cachedDocuments != null) {
      return cachedDocuments;
    }
    final inFlight = _inFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }
    final loadFuture =
        _loadDocumentsUncached(
          normalizedStart: normalizedStart,
          normalizedHome: normalizedHome,
          cacheKey: cacheKey,
        ).whenComplete(() {
          _inFlight.remove(cacheKey);
        });
    _inFlight[cacheKey] = loadFuture;
    return loadFuture;
  }

  Future<List<AiWorkspaceInstructionDocument>> _loadDocumentsUncached({
    required String normalizedStart,
    required String? normalizedHome,
    required String cacheKey,
  }) async {
    final seenPaths = <String>{};
    final documents = <AiWorkspaceInstructionDocument>[];

    Future<void> addDocument(String filePath) async {
      final normalizedPath = p.normalize(filePath);
      if (!seenPaths.add(normalizedPath)) {
        return;
      }
      final file = File(normalizedPath);
      if (!await file.exists()) {
        return;
      }
      try {
        final content = await file.readAsString();
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
      } on FileSystemException {
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

    final directories = <String>[];
    var current = normalizedStart;
    while (true) {
      directories.add(current);
      final parent = p.dirname(current);
      if (parent == current) {
        break;
      }
      current = parent;
    }
    for (final directory in directories.reversed) {
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
    final cached = _cache[cacheKey];
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
      _cache[cacheKey] = _CachedWorkspaceInstructions(
        documents: immutableDocuments,
        cachedAt: _clock().toUtc(),
      );
    }
    return immutableDocuments;
  }

  Future<void> _addRulesDocuments({
    required String rootDirectory,
    required Future<void> Function(String filePath) addDocument,
  }) async {
    final rulesDirectory = Directory(p.join(rootDirectory, '.claude', 'rules'));
    if (!await rulesDirectory.exists()) {
      return;
    }
    final ruleFiles = <String>[];
    await for (final item in rulesDirectory.list()) {
      if (item is! File) continue;
      final normalizedPath = p.normalize(item.path);
      if (normalizedPath.toLowerCase().endsWith('.md')) {
        ruleFiles.add(normalizedPath);
      }
    }
    ruleFiles.sort();
    for (final filePath in ruleFiles) {
      await addDocument(filePath);
    }
  }

  String _truncate(String content) {
    if (content.length <= maxDocumentCharacters) {
      return content;
    }
    return '${content.substring(0, maxDocumentCharacters)}\n\n...[truncated]';
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
