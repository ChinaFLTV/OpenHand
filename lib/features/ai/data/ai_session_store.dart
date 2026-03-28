import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../model/ai_session.dart';

enum AiSessionPersistenceIssueKind { recoveredInvalidFile }

class AiSessionPersistenceIssue {
  const AiSessionPersistenceIssue({
    required this.kind,
    required this.filePath,
    this.detail,
  });

  final AiSessionPersistenceIssueKind kind;
  final String filePath;
  final String? detail;
}

class AiSessionLoadResult {
  const AiSessionLoadResult({required this.sessions, required this.issues});

  final List<AiSession> sessions;
  final List<AiSessionPersistenceIssue> issues;
}

class AiSessionStore {
  static const String _sessionFilePrefix = 'session-';
  static const String _sessionFileSuffix = '.json';
  static const String _invalidSessionBackupPrefix = 'invalid-session-';

  AiSessionStore({String? sessionsDirectoryPath})
    : _sessionsDirectoryPath =
          sessionsDirectoryPath ?? OpenHandPaths.defaultSessionsDirectoryPath();

  final String _sessionsDirectoryPath;

  String get sessionsDirectoryPath => _sessionsDirectoryPath;

  String get attachmentsDirectoryPath =>
      p.join(_sessionsDirectoryPath, 'attachments');

  String sessionAttachmentsDirectoryPath(String sessionId) {
    return p.join(attachmentsDirectoryPath, sessionId);
  }

  String sessionFilePath(String sessionId) {
    return p.join(_sessionsDirectoryPath, 'session-$sessionId.json');
  }

  Future<bool> exists(String sessionId) async {
    return File(sessionFilePath(sessionId)).exists();
  }

  Future<AiSessionLoadResult> loadAll() async {
    final directory = Directory(_sessionsDirectoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      return const AiSessionLoadResult(
        sessions: <AiSession>[],
        issues: <AiSessionPersistenceIssue>[],
      );
    }

    final sessions = <AiSession>[];
    final issues = <AiSessionPersistenceIssue>[];
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final basename = p.basename(entity.path);
      if (!_isPrimarySessionFileName(basename)) {
        continue;
      }
      try {
        final rawContent = await entity.readAsString();
        final decoded = jsonDecode(rawContent);
        if (decoded is! Map) {
          throw const FormatException('Invalid session JSON root.');
        }
        sessions.add(AiSession.fromJson(Map<String, Object?>.from(decoded)));
      } catch (error) {
        final backupPath = await _backupInvalidFile(entity);
        issues.add(
          AiSessionPersistenceIssue(
            kind: AiSessionPersistenceIssueKind.recoveredInvalidFile,
            filePath: backupPath,
            detail: '$error',
          ),
        );
      }
    }

    sessions.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return AiSessionLoadResult(sessions: sessions, issues: issues);
  }

  Future<void> save(AiSession session) async {
    final directory = Directory(_sessionsDirectoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final file = File(sessionFilePath(session.id));
    final content = const JsonEncoder.withIndent(
      '  ',
    ).convert(session.toJson());
    await _writeAtomically(file, content);
  }

  Future<void> delete(String sessionId) async {
    final file = File(sessionFilePath(sessionId));
    if (await file.exists()) {
      await file.delete();
    }
    final attachmentsDirectory = Directory(
      sessionAttachmentsDirectoryPath(sessionId),
    );
    if (await attachmentsDirectory.exists()) {
      await attachmentsDirectory.delete(recursive: true);
    }
  }

  Future<void> openStorageDirectory() async {
    final directory = Directory(_sessionsDirectoryPath);
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

  Future<String> _backupInvalidFile(File sourceFile) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final backupPath = p.join(
      sourceFile.parent.path,
      '$_invalidSessionBackupPrefix${p.basenameWithoutExtension(sourceFile.path)}-$stamp.json',
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

  bool _isPrimarySessionFileName(String basename) {
    if (!basename.startsWith(_sessionFilePrefix) ||
        !basename.endsWith(_sessionFileSuffix)) {
      return false;
    }
    if (basename.startsWith(_invalidSessionBackupPrefix) ||
        basename.contains('.invalid-')) {
      return false;
    }
    return true;
  }
}
