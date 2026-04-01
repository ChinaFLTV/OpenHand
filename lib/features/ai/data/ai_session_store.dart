import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../shared/data/atomic_file_operations.dart';
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

  AiSessionStore({String? sessionsDirectoryPath})
    : _sessionsDirectoryPath =
          sessionsDirectoryPath ?? OpenHandPaths.defaultSessionsDirectoryPath();
  static const String _sessionFilePrefix = 'session-';
  static const String _sessionFileSuffix = '.json';
  static const String _invalidSessionBackupPrefix = 'invalid-session-';

  final String _sessionsDirectoryPath;
  bool _directoryCreated = false;

  String get sessionsDirectoryPath => _sessionsDirectoryPath;

  String get attachmentsDirectoryPath =>
      p.join(_sessionsDirectoryPath, 'attachments');

  String sessionAttachmentsDirectoryPath(String sessionId) {
    return p.join(
      attachmentsDirectoryPath,
      _requireSafeStorageIdentifier(sessionId, label: 'session id'),
    );
  }

  String sessionFilePath(String sessionId) {
    final normalizedSessionId = _requireSafeStorageIdentifier(
      sessionId,
      label: 'session id',
    );
    return p.join(_sessionsDirectoryPath, 'session-$normalizedSessionId.json');
  }

  Future<bool> exists(String sessionId) async {
    final normalizedSessionId = sessionId.trim();
    if (!_isSafeStorageIdentifier(normalizedSessionId)) {
      return false;
    }
    return File(sessionFilePath(normalizedSessionId)).exists();
  }

  Future<AiSessionLoadResult> loadAll() async {
    final directory = Directory(_sessionsDirectoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      _directoryCreated = true;
      return const AiSessionLoadResult(
        sessions: <AiSession>[],
        issues: <AiSessionPersistenceIssue>[],
      );
    }
    _directoryCreated = true;

    final sessions = <AiSession>[];
    final issues = <AiSessionPersistenceIssue>[];
    final seenSessionIds = <String>{};
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
        final session = AiSession.fromJson(Map<String, Object?>.from(decoded));
        _validateSessionForStorage(
          session,
          seenSessionIds: seenSessionIds,
          checkDuplicateSessionIds: true,
        );
        sessions.add(session);
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
    _validateSessionForStorage(session);
    await _ensureDirectoryCreated();
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

  Future<void> openStorageDirectory() {
    return openDirectoryInFileManager(Directory(_sessionsDirectoryPath));
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

  /// Ensures the sessions directory exists, using a cached flag to skip
  /// redundant filesystem checks after the first successful creation.
  Future<void> _ensureDirectoryCreated() async {
    if (_directoryCreated) {
      return;
    }
    final directory = Directory(_sessionsDirectoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _directoryCreated = true;
  }

  Future<void> _writeAtomically(File targetFile, String content) {
    return writeFileAtomically(targetFile, content);
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

final RegExp _unsafeStorageIdentifierPattern = RegExp(
  r'[\u0000-\u001F\u007F/\\]',
);

String _requireSafeStorageIdentifier(String value, {required String label}) {
  final normalizedValue = value.trim();
  if (!_isSafeStorageIdentifier(normalizedValue)) {
    throw FormatException('Invalid $label: $value');
  }
  return normalizedValue;
}

bool _isSafeStorageIdentifier(String value) {
  final normalizedValue = value.trim();
  return normalizedValue.isNotEmpty &&
      normalizedValue != '.' &&
      normalizedValue != '..' &&
      !_unsafeStorageIdentifierPattern.hasMatch(normalizedValue);
}

void _validateSessionForStorage(
  AiSession session, {
  Set<String>? seenSessionIds,
  bool checkDuplicateSessionIds = false,
}) {
  final sessionId = _requireSafeStorageIdentifier(
    session.id,
    label: 'session id',
  );
  if (checkDuplicateSessionIds &&
      seenSessionIds != null &&
      !seenSessionIds.add(sessionId)) {
    throw FormatException('Duplicate session id detected: $sessionId');
  }

  final seenMessageIds = <String>{};
  for (final message in session.messages) {
    final messageId = _requireSafeStorageIdentifier(
      message.id,
      label: 'message id',
    );
    if (!seenMessageIds.add(messageId)) {
      throw FormatException(
        'Duplicate message id detected in session $sessionId: $messageId',
      );
    }
  }
}
