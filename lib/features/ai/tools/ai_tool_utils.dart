import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../service/ai_bash_tool_service.dart';
import '../service/ai_tool_runtime_service.dart';

// 2026-04-01 01:21:38 提取自 AiToolRuntimeService 的共享工具函数
class AiToolUtils {
  AiToolUtils._();

  static const int maxFileCharacters = 64000;
  static const int maxReadBytes = maxFileCharacters * 4;
  static const int maxSearchOutputCharacters = 24000;
  static const int maxWebContentCharacters = 20000;
  static const int maxReadLineLength = 2000;
  static const int defaultReadLimit = 2000;
  static const int maxBinaryPreviewBytes = 32;

  static String defaultWorkingDirectory() {
    return p.normalize(Directory.current.path);
  }

  static String resolvePath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty) return defaultWorkingDirectory();
    if (p.isAbsolute(normalizedInput)) return p.normalize(normalizedInput);
    return p.normalize(p.join(defaultWorkingDirectory(), normalizedInput));
  }

  static Map<String, Object?> decodeArguments(String rawArguments) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
    return const <String, Object?>{};
  }


  static String? requireAbsoluteFilePath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty || !p.isAbsolute(normalizedInput)) return null;
    return p.normalize(normalizedInput);
  }

  static String? requireAbsoluteDirectoryPath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty || !p.isAbsolute(normalizedInput)) return null;
    return p.normalize(normalizedInput);
  }

  static int? readInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value'.trim());
  }

  static List<String> normalizeStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => '$item'.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String truncateContent(String content, int maxCharacters) {
    if (content.length <= maxCharacters) return content;
    return '${content.substring(0, maxCharacters)}...';
  }

  static String htmlToText(String html) {
    final withoutScripts = html
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
    final withoutTags = withoutScripts.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final withoutEntities = withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return withoutEntities.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool globMatches(String value, String pattern) {
    final normalizedValue = value.replaceAll('\\', '/');
    final normalizedPattern = pattern.replaceAll('\\', '/');
    final regex = _globToRegExp(normalizedPattern);
    return regex.hasMatch(normalizedValue) || regex.hasMatch('/$normalizedValue');
  }

  static bool matchesAnyGlob(String value, List<String> patterns) {
    for (final pattern in patterns) {
      if (globMatches(value, pattern)) return true;
    }
    return false;
  }

  static RegExp _globToRegExp(String pattern) {
    final buffer = StringBuffer('^');
    for (var index = 0; index < pattern.length; index++) {
      final char = pattern[index];
      if (char == '*') {
        final isDoubleStar =
            index + 1 < pattern.length && pattern[index + 1] == '*';
        if (isDoubleStar) {
          buffer.write('.*');
          index += 1;
        } else {
          buffer.write('[^/]*');
        }
        continue;
      }
      if (char == '?') { buffer.write('.'); continue; }
      if (r'\\.^$+()[]{}|'.contains(char)) { buffer.write('\\$char'); continue; }
      buffer.write(char);
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  static ReplacementResult replaceOnceOrAll({
    required String content,
    required String oldString,
    required String newString,
    required bool replaceAll,
  }) {
    if (oldString.isEmpty) {
      return const ReplacementResult.failure('old_string must not be empty.');
    }
    final matchCount = RegExp(RegExp.escape(oldString)).allMatches(content).length;
    if (matchCount == 0) {
      return const ReplacementResult.failure('old_string was not found in the file.');
    }
    if (!replaceAll && matchCount > 1) {
      return const ReplacementResult.failure(
          'old_string matched multiple locations. Provide more context or set replace_all.');
    }
    return ReplacementResult.success(
      replaceAll
          ? content.replaceAll(oldString, newString)
          : content.replaceFirst(oldString, newString),
    );
  }

  static AiToolExecutionResult invalidResult(String command, String message) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.invalidArguments,
      command: command,
      workingDirectory: defaultWorkingDirectory(),
      stdout: '',
      stderr: message,
      durationMs: 0,
      resultText: 'status: invalid_arguments\nerror: $message',
    );
  }

  static AiToolExecutionResult simpleSuccessResult({
    required String command,
    required String output,
    required int durationMs,
    String? workingDirectory,
    bool isWriteCommand = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: command,
      workingDirectory: workingDirectory ?? defaultWorkingDirectory(),
      stdout: output,
      stderr: '',
      durationMs: durationMs,
      resultText: output.trim(),
      isWriteCommand: isWriteCommand,
      writeAnalysisReason: isWriteCommand ? 'builtin file mutation tool' : '',
      metadata: metadata,
    );
  }

  static AiToolExecutionResult cancelledResult({
    required String command,
    required int durationMs,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    const detail = 'The tool execution was cancelled by the user.';
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.cancelled,
      command: command,
      workingDirectory: defaultWorkingDirectory(),
      stdout: '',
      stderr: detail,
      durationMs: durationMs,
      resultText: 'status: cancelled\ndetail: $detail',
      metadata: metadata,
    );
  }

  static Future<AiToolExecutionResult?> validateReadBeforeMutation({
    required String toolName,
    required String filePath,
    required Set<String> previouslyReadFiles,
    bool requireExistingFileRead = true,
  }) async {
    if (!requireExistingFileRead) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;
    if (previouslyReadFiles.contains(filePath)) return null;
    return invalidResult(
      toolName,
      '$toolName requires reading the file with Read before mutating it: $filePath',
    );
  }

  static Future<void> writeTextFileSafely(File file, String content) async {
    final entityType = await FileSystemEntity.type(file.path, followLinks: false);
    await file.parent.create(recursive: true);
    if (entityType == FileSystemEntityType.link) {
      await file.writeAsString(content, flush: true);
      return;
    }
    final tempFile = File(p.join(
      file.parent.path,
      '.${p.basename(file.path)}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    ));
    final backupFile = File('${file.path}.bak');
    if (await tempFile.exists()) await tempFile.delete();
    await tempFile.writeAsString(content, flush: true);
    if (await file.exists()) await _copyExistingFileMode(file, tempFile);
    var movedExistingFile = false;
    try {
      if (await backupFile.exists()) await backupFile.delete();
      if (await file.exists()) {
        await file.rename(backupFile.path);
        movedExistingFile = true;
      }
      await tempFile.rename(file.path);
      if (await backupFile.exists()) await backupFile.delete();
    } catch (_) {
      if (await tempFile.exists()) await tempFile.delete();
      if (movedExistingFile && await backupFile.exists()) {
        if (await file.exists()) await file.delete();
        await backupFile.rename(file.path);
      }
      rethrow;
    }
  }

  static Future<void> _copyExistingFileMode(File sourceFile, File targetFile) async {
    if (Platform.isWindows) return;
    final sourceStat = await FileStat.stat(sourceFile.path);
    if (sourceStat.type == FileSystemEntityType.notFound) return;
    final permissionBits = sourceStat.mode & 0x1FF;
    final chmodResult = await Process.run(
        'chmod', <String>[permissionBits.toRadixString(8), targetFile.path]);
    if (chmodResult.exitCode == 0) return;
    final message = '${chmodResult.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty ? 'Unable to preserve existing file permissions.' : message,
      targetFile.path,
    );
  }

  static Future<List<int>> readFilePrefix(File file, int fileLength) async {
    final byteLimit = fileLength < maxReadBytes ? fileLength : maxReadBytes;
    if (byteLimit <= 0) return const <int>[];
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, byteLimit)) {
      builder.add(chunk);
      if (builder.length >= byteLimit) break;
    }
    return builder.takeBytes();
  }

  static String decodeTextBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static bool looksBinary(List<int> bytes) {
    final preview = bytes.take(2048);
    var suspiciousCount = 0;
    var inspected = 0;
    for (final value in preview) {
      inspected += 1;
      if (value == 0) return true;
      final isControl = value < 32 && value != 9 && value != 10 && value != 13;
      if (isControl) suspiciousCount += 1;
    }
    if (inspected == 0) return false;
    return suspiciousCount / inspected > 0.12;
  }

  static bool isRasterImageExtension(String extension) {
    return const <String>{
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico', '.tga'
    }.contains(extension);
  }

  static bool isKnownTextExtension(String extension) {
    if (extension.isEmpty) return false;
    return const <String>{
      '.txt', '.md', '.markdown', '.json', '.yaml', '.yml', '.toml', '.xml',
      '.html', '.htm', '.css', '.scss', '.sass', '.js', '.jsx', '.ts', '.tsx',
      '.dart', '.go', '.py', '.java', '.kt', '.kts', '.rb', '.rs', '.c',
      '.cc', '.cpp', '.h', '.hpp', '.sh', '.zsh', '.bash', '.fish', '.sql',
      '.csv', '.tsv', '.env', '.ini', '.cfg', '.conf', '.log', '.svg', '.vue',
    }.contains(extension);
  }

  static bool looksLikeTimeoutMessage(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized.contains('timed out') || normalized.contains('timeout');
  }

  static Future<T?> awaitWithCancellation<T>(
    Future<T> future, {
    Future<void>? cancelSignal,
  }) async {
    if (cancelSignal == null) return future;
    final sentinel = Object();
    final firstResult = await Future.any(<Future<Object?>?>[
      future,
      cancelSignal.then<Object?>((_) => sentinel),
    ].whereType<Future<Object?>>().toList());
    if (identical(firstResult, sentinel)) {
      future.then<void>((_) {}, onError: (Object e, StackTrace st) {});
      return null;
    }
    return firstResult as T;
  }
}

class ReplacementResult {
  const ReplacementResult.success(this.content)
      : success = true,
        errorMessage = '';
  const ReplacementResult.failure(this.errorMessage)
      : success = false,
        content = '';

  final bool success;
  final String content;
  final String errorMessage;
}
