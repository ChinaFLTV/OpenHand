import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/ai_session_runtime_context.dart';

class AiWorkspaceInstructionService {
  AiWorkspaceInstructionService({
    DateTime Function()? clock,
    Duration cacheTtl = const Duration(seconds: 3),
  }) : _clock = clock ?? DateTime.now,
       _cacheTtl = cacheTtl;

  static const int _maxDocumentCharacters = 16000;
  static const List<String> _workspaceInstructionFiles = <String>[
    'AGENTS.md',
    'CLAUDE.md',
  ];
  final DateTime Function() _clock;
  final Duration _cacheTtl;
  final Map<String, _CachedWorkspaceInstructions> _cache =
      <String, _CachedWorkspaceInstructions>{};

  List<AiWorkspaceInstructionDocument> loadDocuments({
    required String startDirectory,
    String? homeDirectory,
  }) {
    final normalizedStart = p.normalize(startDirectory.trim());
    if (normalizedStart.isEmpty || !Directory(normalizedStart).existsSync()) {
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
    final seenPaths = <String>{};
    final documents = <AiWorkspaceInstructionDocument>[];

    void addDocument(String filePath) {
      final normalizedPath = p.normalize(filePath);
      if (!seenPaths.add(normalizedPath)) {
        return;
      }
      final file = File(normalizedPath);
      if (!file.existsSync()) {
        return;
      }
      try {
        final content = file.readAsStringSync();
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
      addDocument(p.join(normalizedHome, '.claude', 'CLAUDE.md'));
      _addRulesDocuments(
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
        addDocument(p.join(directory, fileName));
      }
      _addRulesDocuments(rootDirectory: directory, addDocument: addDocument);
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

  void _addRulesDocuments({
    required String rootDirectory,
    required void Function(String filePath) addDocument,
  }) {
    final rulesDirectory = Directory(p.join(rootDirectory, '.claude', 'rules'));
    if (!rulesDirectory.existsSync()) {
      return;
    }
    final ruleFiles =
        rulesDirectory
            .listSync(recursive: false)
            .whereType<File>()
            .map((item) => p.normalize(item.path))
            .where((item) => item.toLowerCase().endsWith('.md'))
            .toList(growable: false)
          ..sort();
    for (final filePath in ruleFiles) {
      addDocument(filePath);
    }
  }

  String _truncate(String content) {
    if (content.length <= _maxDocumentCharacters) {
      return content;
    }
    return '${content.substring(0, _maxDocumentCharacters)}\n\n...[truncated]';
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
