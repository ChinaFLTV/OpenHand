import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../model/user_memory_entry.dart';

enum MemoryPersistenceIssueKind {
  recoveredInvalidFile,
  sanitizedInvalidContent,
  saveFailed,
}

class MemoryPersistenceIssue {
  const MemoryPersistenceIssue({
    required this.kind,
    required this.filePath,
    this.detail,
  });

  final MemoryPersistenceIssueKind kind;
  final String filePath;
  final String? detail;
}

class MemoryLoadResult {
  const MemoryLoadResult({required this.entries, this.issue});

  final List<UserMemoryEntry> entries;
  final MemoryPersistenceIssue? issue;
}

class MemoryStore {
  MemoryStore({String? userMemoryFilePath})
    : _userMemoryFilePath =
          userMemoryFilePath ?? OpenHandPaths.defaultUserMemoryFilePath();

  final String _userMemoryFilePath;

  String get userMemoryFilePath => _userMemoryFilePath;
  String get storageDirectoryPath => p.dirname(_userMemoryFilePath);

  Future<MemoryLoadResult> load() async {
    final targetFile = File(_userMemoryFilePath);
    if (!await targetFile.exists()) {
      final entries = const <UserMemoryEntry>[];
      try {
        await save(entries);
        return const MemoryLoadResult(entries: <UserMemoryEntry>[]);
      } catch (error) {
        return MemoryLoadResult(
          entries: entries,
          issue: MemoryPersistenceIssue(
            kind: MemoryPersistenceIssueKind.saveFailed,
            filePath: _userMemoryFilePath,
            detail: '$error',
          ),
        );
      }
    }

    late final String rawContent;
    try {
      rawContent = await targetFile.readAsString();
    } catch (error) {
      return MemoryLoadResult(
        entries: const <UserMemoryEntry>[],
        issue: MemoryPersistenceIssue(
          kind: MemoryPersistenceIssueKind.saveFailed,
          filePath: _userMemoryFilePath,
          detail: '$error',
        ),
      );
    }

    try {
      final decoded = jsonDecode(rawContent);
      final sanitized = _sanitize(decoded);
      if (!sanitized.didSanitize) {
        return MemoryLoadResult(entries: sanitized.entries);
      }
      try {
        await save(sanitized.entries);
        return MemoryLoadResult(
          entries: sanitized.entries,
          issue: MemoryPersistenceIssue(
            kind: MemoryPersistenceIssueKind.sanitizedInvalidContent,
            filePath: _userMemoryFilePath,
          ),
        );
      } catch (error) {
        return MemoryLoadResult(
          entries: sanitized.entries,
          issue: MemoryPersistenceIssue(
            kind: MemoryPersistenceIssueKind.saveFailed,
            filePath: _userMemoryFilePath,
            detail: '$error',
          ),
        );
      }
    } catch (error) {
      try {
        final backupPath = await _backupInvalidFile(targetFile);
        await save(const <UserMemoryEntry>[]);
        return MemoryLoadResult(
          entries: const <UserMemoryEntry>[],
          issue: MemoryPersistenceIssue(
            kind: MemoryPersistenceIssueKind.recoveredInvalidFile,
            filePath: backupPath,
            detail: '$error',
          ),
        );
      } catch (saveError) {
        return MemoryLoadResult(
          entries: const <UserMemoryEntry>[],
          issue: MemoryPersistenceIssue(
            kind: MemoryPersistenceIssueKind.saveFailed,
            filePath: _userMemoryFilePath,
            detail: '$error\n$saveError',
          ),
        );
      }
    }
  }

  Future<void> save(List<UserMemoryEntry> entries) async {
    final targetFile = File(_userMemoryFilePath);
    final targetDirectory = targetFile.parent;
    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }
    final content = _encode(entries);
    await _writeAtomically(targetFile, content);
  }

  _SanitizedMemoryResult _sanitize(Object? decoded) {
    if (decoded is! List) {
      throw const FormatException('Root JSON is invalid.');
    }

    var didSanitize = false;
    final entries = <UserMemoryEntry>[];
    final seenIds = <String>{};

    for (final rawEntry in decoded) {
      final parsedEntry = _parseEntry(rawEntry);
      if (parsedEntry == null) {
        didSanitize = true;
        continue;
      }
      if (!seenIds.add(parsedEntry.entry.id)) {
        didSanitize = true;
        continue;
      }
      if (parsedEntry.didSanitize) {
        didSanitize = true;
      }
      entries.add(parsedEntry.entry);
    }

    entries.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return _SanitizedMemoryResult(didSanitize: didSanitize, entries: entries);
  }

  _ParsedMemoryEntry? _parseEntry(Object? rawEntry) {
    if (rawEntry is! Map) {
      return null;
    }
    final id = '${rawEntry['id'] ?? ''}'.trim();
    final createdAtRaw = '${rawEntry['created_at'] ?? ''}'.trim();
    final content = UserMemoryEntry.normalizeContent(
      '${rawEntry['content'] ?? ''}',
    );
    if (id.isEmpty || createdAtRaw.isEmpty || content.isEmpty) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      return null;
    }

    var didSanitize = false;
    final rawType = '${rawEntry['type'] ?? ''}'.trim();
    final type = rawType == UserMemoryEntry.userType
        ? UserMemoryEntry.userType
        : UserMemoryEntry.userType;
    if (rawType != UserMemoryEntry.userType) {
      didSanitize = true;
    }

    final rawTags = rawEntry['tags'];
    List<String> tags;
    if (rawTags is List) {
      tags = UserMemoryEntry.normalizeTags(rawTags.map((item) => '$item'));
      if (tags.length != rawTags.length) {
        didSanitize = true;
      }
    } else if (rawTags == null) {
      tags = const <String>[];
      didSanitize = true;
    } else {
      tags = const <String>[];
      didSanitize = true;
    }

    return _ParsedMemoryEntry(
      entry: UserMemoryEntry(
        id: id,
        type: type,
        createdAt: createdAt.toUtc(),
        content: content,
        tags: tags,
      ),
      didSanitize: didSanitize,
    );
  }

  String _encode(List<UserMemoryEntry> entries) {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(entries.map((entry) => entry.toJson()).toList(growable: false));
  }

  Future<String> _backupInvalidFile(File sourceFile) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final backupPath = p.join(
      sourceFile.parent.path,
      'user-memory.invalid-$stamp.json',
    );
    final backupFile = File(backupPath);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    await sourceFile.rename(backupPath);
    return backupPath;
  }

  Future<void> _writeAtomically(File targetFile, String content) async {
    final tempFile = File('${targetFile.path}.tmp');
    final backupFile = File('${targetFile.path}.bak');

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await tempFile.writeAsString(content, flush: true);

    var movedExistingFile = false;
    try {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      if (await targetFile.exists()) {
        await targetFile.rename(backupFile.path);
        movedExistingFile = true;
      }
      await tempFile.rename(targetFile.path);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (movedExistingFile && await backupFile.exists()) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await backupFile.rename(targetFile.path);
      }
      rethrow;
    }
  }

  Future<void> openStorageDirectory() async {
    final directory = Directory(storageDirectoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    late final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('open', <String>[directory.path]);
    } else if (Platform.isWindows) {
      result = await Process.run('explorer', <String>[directory.path]);
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[directory.path]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }

    if (result.exitCode != 0) {
      final message = '${result.stderr}'.trim();
      throw FileSystemException(
        message.isEmpty ? 'Unable to open directory.' : message,
      );
    }
  }
}

class _ParsedMemoryEntry {
  const _ParsedMemoryEntry({required this.entry, required this.didSanitize});

  final UserMemoryEntry entry;
  final bool didSanitize;
}

class _SanitizedMemoryResult {
  const _SanitizedMemoryResult({
    required this.didSanitize,
    required this.entries,
  });

  final bool didSanitize;
  final List<UserMemoryEntry> entries;
}
