import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../app/support/silent_log.dart';
import '../../../shared/util/byte_size_format.dart';
import '../service/bash/ai_bash_tool_service.dart';
import '../service/fs/ai_file_history_service.dart';
import '../service/fs/ai_file_mutation_ledger.dart';
import '../service/fs/ai_file_tracker_service.dart';
import '../service/runtime/ai_tool_runtime_service.dart';

class AiToolUtils {
  AiToolUtils._();

  static const int maxFileCharacters = 64000;
  static const int maxReadBytes = maxFileCharacters * 4;
  static const int maxSearchOutputCharacters = 24000;
  static const int maxWebContentCharacters = 20000;
  static const int maxReadLineLength = 2000;
  static const int defaultReadLimit = 2000;
  static const int maxBinaryPreviewBytes = 32;
  static const int maxLedgerCaptureBytes = 16 * kBytesPerMiB;
  static const int maxEditableTextFileBytes = 128 * kBytesPerMiB;

  static String defaultWorkingDirectory() {
    return p.normalize(Directory.current.path);
  }

  static String resolvePath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty) return defaultWorkingDirectory();
    if (p.isAbsolute(normalizedInput)) return p.normalize(normalizedInput);
    return p.normalize(p.join(defaultWorkingDirectory(), normalizedInput));
  }

  static Map<String, Object?> decodeArguments(
    String rawArguments, {
    Map<String, Object?>? parameters,
  }) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map<String, Object?>) {
        return _coerceArgumentMap(decoded, parameters: parameters);
      }
      if (decoded is Map) {
        return _coerceArgumentMap(
          Map<String, Object?>.from(decoded),
          parameters: parameters,
        );
      }
    } catch (error, stack) {
      silentLog('ai_tool_utils', 'decode tool arguments JSON', error, stack);
    }
    return const <String, Object?>{};
  }

  /// Heuristic post-processor that "unwraps" common malformed argument
  /// shapes produced by less-capable models, so downstream tools see a
  /// schema-compliant payload on first call:
  ///
  ///   1. `{"_raw": "<query>foo</query>"}`
  ///         → parses inline XML/CDATA tags and lifts each into top-level
  ///           keys (e.g. `{query: "foo"}`).
  ///   2. `{"todos": {"item": [...]}}`
  ///         → flattens single-key XML-style array wrappers
  ///           (`item` / `items` / `entry` / `entries` / `value` / `values`)
  ///           into a plain list (e.g. `{todos: [...]}`).
  ///   3. `{"query": "<![CDATA[foo]]>"}`
  ///         → strips CDATA wrappers from string values.
  static Map<String, Object?> _coerceArgumentMap(
    Map<String, Object?> input, {
    Map<String, Object?>? parameters,
  }) {
    final result = <String, Object?>{};
    final propertySchemas = _propertySchemas(parameters);
    Map<String, Object?> rawExtracted = const <String, Object?>{};
    for (final entry in input.entries) {
      if (entry.key == '_raw' && entry.value is String) {
        rawExtracted = _extractFromXmlBlob('${entry.value}');
        continue;
      }
      result[entry.key] = _coerceArgumentValue(
        entry.value,
        schema: propertySchemas[entry.key],
      );
    }
    // Merge _raw-extracted keys without overwriting explicit keys.
    for (final entry in rawExtracted.entries) {
      result.putIfAbsent(entry.key, () => entry.value);
    }
    // 2026-05-02: tolerance — weaker models often over-wrap parameter
    // payloads as `{key: {key: [...]}}` (e.g. `todos: {todos: [...]}`)
    // when shoe-horning JSON into DSML parameters. Detect this single
    // case and unwrap once so downstream tools see the canonical shape.
    final unwrapped = <String, Object?>{};
    var didUnwrap = false;
    for (final entry in result.entries) {
      final value = entry.value;
      if (value is Map &&
          value.length == 1 &&
          value.keys.first.toString().toLowerCase() ==
              entry.key.toLowerCase()) {
        unwrapped[entry.key] = _coerceArgumentValue(
          value.values.first,
          schema: propertySchemas[entry.key],
        );
        didUnwrap = true;
      } else {
        unwrapped[entry.key] = value;
      }
    }
    return didUnwrap ? unwrapped : result;
  }

  static Object? _coerceArgumentValue(
    Object? value, {
    Map<String, Object?>? schema,
  }) {
    if (value is String) {
      final stripped = _stripCdata(value);
      // 2026-05-02: tolerance — weaker models frequently emit JSON-shaped
      // strings (`"[{...}, ...]"`, `"{\"todos\":[...]}"`) inside DSML
      // parameter slots that the downstream tool expects to receive as
      // a typed List/Map. Decode only when the current tool schema asks for
      // a non-string shape; otherwise JSON file contents for tools like Write
      // must remain exact strings.
      final trimmed = stripped.trim();
      final schemaType = _schemaType(schema);
      if (schemaType == 'array' || schemaType == 'object') {
        final decoded = _tryDecodeJson(trimmed);
        if (decoded != null) {
          return _coerceArgumentValue(decoded, schema: schema);
        }
      }
      if (schemaType == 'integer' || schemaType == 'number') {
        final decoded = _tryDecodeJson(trimmed);
        if (decoded is num) return decoded;
        final parsed = num.tryParse(trimmed);
        if (parsed != null) return parsed;
      }
      if (schemaType == 'boolean') {
        final decoded = _tryDecodeJson(trimmed);
        if (decoded is bool) return decoded;
        final normalized = trimmed.toLowerCase();
        if (normalized == 'true' || normalized == 'false') {
          return normalized == 'true';
        }
      }
      return stripped;
    }
    if (value is Map) {
      final asMap = Map<String, Object?>.from(value);
      // Single-key XML-style array wrappers: {item:[...]} → [...]
      if (asMap.length == 1) {
        final onlyKey = asMap.keys.first.toLowerCase();
        const arrayWrapperKeys = <String>{
          'item',
          'items',
          'entry',
          'entries',
          'value',
          'values',
          'element',
          'elements',
        };
        if (arrayWrapperKeys.contains(onlyKey) && asMap.values.first is List) {
          return (asMap.values.first as List)
              .map((item) => _coerceArgumentValue(item, schema: schema))
              .toList(growable: false);
        }
      }
      final propertySchemas = _propertySchemas(schema);
      return asMap.map(
        (k, v) => MapEntry(
          k.toString(),
          _coerceArgumentValue(v, schema: propertySchemas[k.toString()]),
        ),
      );
    }
    if (value is List) {
      final itemSchema = _itemSchema(schema);
      return value
          .map((item) => _coerceArgumentValue(item, schema: itemSchema))
          .toList(growable: false);
    }
    return value;
  }

  static Map<String, Map<String, Object?>> _propertySchemas(
    Map<String, Object?>? schema,
  ) {
    final properties = schema?['properties'];
    if (properties is! Map) return const <String, Map<String, Object?>>{};
    final result = <String, Map<String, Object?>>{};
    for (final entry in properties.entries) {
      final key = '${entry.key}';
      final value = entry.value;
      if (value is Map<String, Object?>) {
        result[key] = value;
      } else if (value is Map) {
        result[key] = Map<String, Object?>.from(value);
      }
    }
    return result;
  }

  static Map<String, Object?>? _itemSchema(Map<String, Object?>? schema) {
    final items = schema?['items'];
    if (items is Map<String, Object?>) return items;
    if (items is Map) return Map<String, Object?>.from(items);
    return null;
  }

  static String _schemaType(Map<String, Object?>? schema) {
    final type = schema?['type'];
    if (type is String) return type.trim().toLowerCase();
    if (type is List) {
      for (final item in type) {
        final value = '$item'.trim().toLowerCase();
        if (value.isNotEmpty && value != 'null') return value;
      }
    }
    return '';
  }

  static Object? _tryDecodeJson(String value) {
    if (value.isEmpty) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  static String _stripCdata(String value) {
    final cdataPattern = RegExp(
      r'<!\[CDATA\[([\s\S]*?)\]\]>',
      caseSensitive: false,
    );
    if (!cdataPattern.hasMatch(value)) return value;
    return value.replaceAllMapped(cdataPattern, (m) => m.group(1) ?? '');
  }

  /// Best-effort extraction of `<key>value</key>` (and `<key/>`) pairs from
  /// a free-form XML blob. CDATA wrappers are stripped. Mismatched closing
  /// tags are tolerated by collecting the inner text up to the next
  /// `</something>` token.
  static Map<String, Object?> _extractFromXmlBlob(String blob) {
    final out = <String, Object?>{};
    final tagPattern = RegExp(
      r'<\s*([A-Za-z_][\w-]*)\s*>([\s\S]*?)</\s*[A-Za-z_][\w-]*\s*>',
    );
    for (final match in tagPattern.allMatches(blob)) {
      final key = (match.group(1) ?? '').trim();
      if (key.isEmpty || key.startsWith('!') || key.startsWith('?')) continue;
      final raw = (match.group(2) ?? '').trim();
      out[key] = _stripCdata(raw);
    }
    return out;
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
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          ' ',
        );
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
    return regex.hasMatch(normalizedValue) ||
        regex.hasMatch('/$normalizedValue');
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
      if (char == '?') {
        buffer.write('.');
        continue;
      }
      if (r'\\.^$+()[]{}|'.contains(char)) {
        buffer.write('\\$char');
        continue;
      }
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
    final actualOldString = findActualString(content, oldString);
    if (actualOldString == null) {
      return const ReplacementResult.failure(
        'old_string was not found in the file.',
      );
    }
    final actualNewString = preserveQuoteStyle(
      oldString,
      actualOldString,
      newString,
    );
    final matchCount = RegExp(
      RegExp.escape(actualOldString),
    ).allMatches(content).length;
    if (matchCount == 0) {
      return const ReplacementResult.failure(
        'old_string was not found in the file.',
      );
    }
    if (!replaceAll && matchCount > 1) {
      return const ReplacementResult.failure(
        'old_string matched multiple locations. Provide more context or set replace_all.',
      );
    }
    return ReplacementResult.success(
      replaceAll
          ? content.replaceAll(actualOldString, actualNewString)
          : content.replaceFirst(actualOldString, actualNewString),
      appliedNewString: actualNewString,
      matchedOldString: actualOldString,
      replacementCount: replaceAll ? matchCount : 1,
    );
  }

  static ReplacementResult applyExactStringEdit({
    required String content,
    required String oldString,
    required String newString,
    required bool replaceAll,
    required bool allowCreationFromEmptyOldString,
  }) {
    final normalizedOldString = normalizeTextLineEndings(oldString);
    final normalizedNewString = normalizeTextLineEndings(newString);
    if (normalizedOldString.isEmpty) {
      if (!allowCreationFromEmptyOldString && content.trim().isNotEmpty) {
        return const ReplacementResult.failure(
          'old_string must not be empty. Empty old_string is only allowed when '
          'creating a new file or replacing an empty file.',
        );
      }
      if (replaceAll) {
        return const ReplacementResult.failure(
          'replace_all is not valid when old_string is empty.',
        );
      }
      return ReplacementResult.success(
        normalizedNewString,
        appliedNewString: normalizedNewString,
      );
    }
    if (normalizedOldString == normalizedNewString) {
      return const ReplacementResult.failure(
        'old_string and new_string must differ.',
      );
    }
    return replaceOnceOrAll(
      content: content,
      oldString: normalizedOldString,
      newString: normalizedNewString,
      replaceAll: replaceAll,
    );
  }

  static String? validateSequentialEditTarget({
    required String oldString,
    required Iterable<String> previousNewStrings,
  }) {
    final oldStringToCheck = normalizeTextLineEndings(
      oldString,
    ).replaceAll(RegExp(r'\n+$'), '');
    if (oldStringToCheck.isEmpty) return null;
    for (final previousNewString in previousNewStrings) {
      if (normalizeTextLineEndings(
        previousNewString,
      ).contains(oldStringToCheck)) {
        return 'Cannot edit file: old_string is a substring of a new_string '
            'from a previous edit.';
      }
    }
    return null;
  }

  static String normalizeQuotes(String value) {
    return value
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"');
  }

  static String? findActualString(String content, String searchString) {
    if (content.contains(searchString)) return searchString;
    final normalizedSearch = normalizeQuotes(searchString);
    final normalizedContent = normalizeQuotes(content);
    final matchIndex = normalizedContent.indexOf(normalizedSearch);
    if (matchIndex < 0) return null;
    return content.substring(matchIndex, matchIndex + searchString.length);
  }

  static String preserveQuoteStyle(
    String oldString,
    String actualOldString,
    String newString,
  ) {
    if (oldString == actualOldString) return newString;
    var result = newString;
    if (actualOldString.contains('\u201c') ||
        actualOldString.contains('\u201d')) {
      result = _applyCurlyDoubleQuotes(result);
    }
    if (actualOldString.contains('\u2018') ||
        actualOldString.contains('\u2019')) {
      result = _applyCurlySingleQuotes(result);
    }
    return result;
  }

  static String _applyCurlyDoubleQuotes(String value) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char == '"') {
        buffer.write(_isOpeningQuoteContext(value, i) ? '\u201c' : '\u201d');
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static String _applyCurlySingleQuotes(String value) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char != "'") {
        buffer.write(char);
        continue;
      }
      final prev = i > 0 ? value[i - 1] : '';
      final next = i + 1 < value.length ? value[i + 1] : '';
      if (_isAsciiLetter(prev) && _isAsciiLetter(next)) {
        buffer.write('\u2019');
      } else {
        buffer.write(_isOpeningQuoteContext(value, i) ? '\u2018' : '\u2019');
      }
    }
    return buffer.toString();
  }

  static bool _isOpeningQuoteContext(String value, int index) {
    if (index == 0) return true;
    final previous = value[index - 1];
    return previous == ' ' ||
        previous == '\t' ||
        previous == '\n' ||
        previous == '\r' ||
        previous == '(' ||
        previous == '[' ||
        previous == '{' ||
        previous == '\u2014' ||
        previous == '\u2013';
  }

  static bool _isAsciiLetter(String value) {
    if (value.isEmpty) return false;
    final code = value.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  static Future<AiEditableTextSnapshot> readEditableTextFile(File file) async {
    final stat = await file.stat();
    if (stat.size > maxEditableTextFileBytes) {
      throw AiEditableTextFileTooLargeException(
        filePath: file.path,
        sizeBytes: stat.size,
        limitBytes: maxEditableTextFileBytes,
      );
    }
    final rawContent = await file.readAsString();
    return AiEditableTextSnapshot.fromRaw(rawContent);
  }

  static String normalizeTextLineEndings(String value) {
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
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
    String? writeAnalysisReason,
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
      writeAnalysisReason: isWriteCommand
          ? (writeAnalysisReason ?? 'builtin file mutation tool')
          : '',
      metadata: metadata,
    );
  }

  static AiToolExecutionResult withMergedMetadata(
    AiToolExecutionResult result,
    Map<String, Object?> metadata,
  ) {
    if (metadata.isEmpty) return result;
    return AiToolExecutionResult(
      status: result.status,
      command: result.command,
      workingDirectory: result.workingDirectory,
      stdout: result.stdout,
      stderr: result.stderr,
      durationMs: result.durationMs,
      resultText: result.resultText,
      exitCode: result.exitCode,
      matchedRuleId: result.matchedRuleId,
      matchedRulePattern: result.matchedRulePattern,
      isWriteCommand: result.isWriteCommand,
      writeAnalysisReason: result.writeAnalysisReason,
      metadata: <String, Object?>{...result.metadata, ...metadata},
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
    AiFileTrackerService? fileTracker,
  }) async {
    if (!requireExistingFileRead) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;
    if (!previouslyReadFiles.contains(filePath)) {
      return invalidResult(
        toolName,
        '$toolName requires reading the file with Read before mutating it: $filePath',
      );
    }

    // 2026-04-12: 脏写检测 - 检查文件是否在读取后被外部修改
    if (fileTracker != null) {
      final dirtyWriteError = await fileTracker.validateSafeToWrite(filePath);
      if (dirtyWriteError != null) {
        return invalidResult(toolName, dirtyWriteError);
      }
    }

    return null;
  }

  /// 在文件修改前保存历史版本
  ///
  /// 2026-04-12: 实现 OpenCode 历史版本机制
  static Future<String?> saveFileVersionBeforeMutation({
    required String filePath,
    required String sessionId,
    String? toolCallId,
    AiFileHistoryService? fileHistory,
  }) async {
    if (fileHistory == null) return null;
    return fileHistory.saveVersion(
      filePath: filePath,
      sessionId: sessionId,
      toolCallId: toolCallId,
    );
  }

  /// 在文件修改后更新追踪器
  ///
  /// 2026-04-12: 写入成功后更新 lastReadTime
  static Future<void> updateTrackerAfterMutation({
    required String filePath,
    AiFileTrackerService? fileTracker,
  }) async {
    if (fileTracker == null) return;
    await fileTracker.updateAfterWrite(filePath);
  }

  /// 2026-05-03 — 把一次工具产生的文件级变动写入新的 [AiFileMutationLedger]，
  /// 同时落 before/after 两份内容，供 UI 层 diff/undo/redo 使用。
  ///
  /// 调用契约（任一字段缺失都会优雅降级）：
  ///   • [beforeContent] = 修改前磁盘内容；新建文件传 null。
  ///   • [afterContent] = 修改后磁盘内容；删除文件传 null。
  ///
  /// 返回写入成功的 recordId，便于在工具的 result metadata 上回填，UI 据
  /// 此把卡片关联到 ledger 记录。
  static Future<String?> recordFileMutationToLedger({
    required AiFileMutationLedger? ledger,
    required String sessionId,
    required String toolCallId,
    required String toolName,
    required String filePath,
    required FileMutationKind kind,
    required String? beforeContent,
    required String? afterContent,
  }) async {
    if (ledger == null) return null;
    final record = await ledger.recordMutation(
      sessionId: sessionId,
      toolCallId: toolCallId,
      toolName: toolName,
      filePath: filePath,
      kind: kind,
      beforeContent: beforeContent,
      afterContent: afterContent,
    );
    return record?.recordId;
  }

  /// 安全读取 UTF-8 文本内容；不存在或不可读时返回 null。用于工具在写入
  /// 前后捕获 before/after 快照。失败仅 silentLog，不抛出。
  static Future<String?> readFileContentForLedger(String filePath) async {
    try {
      final f = File(filePath);
      if (!await f.exists()) return null;
      final stat = await f.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      // 限制单文件 16 MB，超过则放弃捕获（避免 OOM）。
      if (stat.size > maxLedgerCaptureBytes) return null;
      return await f.readAsString();
    } catch (error, stack) {
      silentLog('ai_tool_utils', 'readFileContentForLedger', error, stack);
      return null;
    }
  }

  static Future<void> writeTextFileSafely(File file, String content) async {
    final entityType = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );
    await file.parent.create(recursive: true);
    if (entityType == FileSystemEntityType.link) {
      await file.writeAsString(content, flush: true);
      return;
    }
    final tempFile = File(
      p.join(
        file.parent.path,
        '.${p.basename(file.path)}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
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

  /// Performs the last read-before-write guard immediately before writing.
  ///
  /// Tools may still run an earlier validation to fail fast. This final guard
  /// stays adjacent to the disk write so confirmation dialogs, history capture,
  /// or ledger reads cannot leave a stale write window unprotected.
  static Future<AiToolExecutionResult?> writeTextFileWithMutationGuard({
    required String toolName,
    required File file,
    required String content,
    required Set<String> previouslyReadFiles,
    required bool requireExistingFileRead,
    AiFileTrackerService? fileTracker,
  }) async {
    if (!requireExistingFileRead && await file.exists()) {
      return invalidResult(
        toolName,
        '$toolName expected to create a new file, but the target now exists. '
        'Read the file before overwriting it: ${file.path}',
      );
    }

    final readValidation = await validateReadBeforeMutation(
      toolName: toolName,
      filePath: file.path,
      previouslyReadFiles: previouslyReadFiles,
      requireExistingFileRead: requireExistingFileRead,
      fileTracker: fileTracker,
    );
    if (readValidation != null) return readValidation;

    await writeTextFileSafely(file, content);
    await updateTrackerAfterMutation(
      filePath: file.path,
      fileTracker: fileTracker,
    );
    return null;
  }

  /// Performs the last read-before-delete guard immediately before deletion.
  static Future<AiToolExecutionResult?> deleteFileWithMutationGuard({
    required String toolName,
    required File file,
    required Set<String> previouslyReadFiles,
    AiFileTrackerService? fileTracker,
  }) async {
    final readValidation = await validateReadBeforeMutation(
      toolName: toolName,
      filePath: file.path,
      previouslyReadFiles: previouslyReadFiles,
      fileTracker: fileTracker,
    );
    if (readValidation != null) return readValidation;

    final entityType = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.notFound) {
      return invalidResult(
        toolName,
        '$toolName target no longer exists before deletion. Re-read the path before retrying: ${file.path}',
      );
    }
    if (entityType == FileSystemEntityType.directory) {
      return invalidResult(
        toolName,
        '$toolName refuses to delete a directory: ${file.path}',
      );
    }

    await file.delete();
    await updateTrackerAfterMutation(
      filePath: file.path,
      fileTracker: fileTracker,
    );
    return null;
  }

  static Future<void> _copyExistingFileMode(
    File sourceFile,
    File targetFile,
  ) async {
    if (Platform.isWindows) return;
    final sourceStat = await FileStat.stat(sourceFile.path);
    if (sourceStat.type == FileSystemEntityType.notFound) return;
    final permissionBits = sourceStat.mode & 0x1FF;
    final chmodResult = await Process.run('chmod', <String>[
      permissionBits.toRadixString(8),
      targetFile.path,
    ]);
    if (chmodResult.exitCode == 0) return;
    final message = '${chmodResult.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty
          ? 'Unable to preserve existing file permissions.'
          : message,
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
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.ico',
      '.tga',
    }.contains(extension);
  }

  static bool isKnownTextExtension(String extension) {
    if (extension.isEmpty) return false;
    return const <String>{
      '.txt',
      '.md',
      '.markdown',
      '.json',
      '.yaml',
      '.yml',
      '.toml',
      '.xml',
      '.html',
      '.htm',
      '.css',
      '.scss',
      '.sass',
      '.js',
      '.jsx',
      '.ts',
      '.tsx',
      '.dart',
      '.go',
      '.py',
      '.java',
      '.kt',
      '.kts',
      '.rb',
      '.rs',
      '.c',
      '.cc',
      '.cpp',
      '.h',
      '.hpp',
      '.sh',
      '.zsh',
      '.bash',
      '.fish',
      '.sql',
      '.csv',
      '.tsv',
      '.env',
      '.ini',
      '.cfg',
      '.conf',
      '.log',
      '.svg',
      '.vue',
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
    final firstResult = await Future.any(
      <Future<Object?>?>[
        future,
        cancelSignal.then<Object?>((_) => sentinel),
      ].whereType<Future<Object?>>().toList(),
    );
    if (identical(firstResult, sentinel)) {
      future.then<void>((_) {}, onError: (Object e, StackTrace st) {});
      return null;
    }
    return firstResult as T;
  }

  // ────────────────────────────────────────────────────────────
  // 2026-04-13: ripgrep (rg) 命令路径解析
  // 优先使用应用内嵌入的 rg，确保用户无需预装 ripgrep
  // ────────────────────────────────────────────────────────────

  /// 缓存的 rg 可执行文件路径。首次调用时初始化。
  static String? _cachedRgPath;

  /// 获取当前平台的 ripgrep 子目录名称。
  ///
  /// 返回格式：`{arch}-{os}`，例如 `arm64-darwin`、`x64-win32`。
  static String _getRipgrepPlatformDir() {
    final String os;
    if (Platform.isMacOS) {
      os = 'darwin';
    } else if (Platform.isWindows) {
      os = 'win32';
    } else if (Platform.isLinux) {
      os = 'linux';
    } else {
      os = 'unknown';
    }

    // 检测 CPU 架构
    // Dart 没有直接的 API，通过 Platform.version 或环境变量推断
    final String arch;
    final version = Platform.version.toLowerCase();
    final executable = Platform.resolvedExecutable.toLowerCase();

    if (Platform.isMacOS) {
      // macOS: 通过可执行文件路径或 uname 推断
      // Apple Silicon 通常在 arm64 目录，Intel 在 x86_64
      // 简化判断：如果路径包含 arm64 或 M1/M2/M3 系列，使用 arm64
      if (executable.contains('arm64') || _isAppleSilicon()) {
        arch = 'arm64';
      } else {
        arch = 'x64';
      }
    } else if (Platform.isWindows) {
      // Windows: 检查环境变量
      final processorArch =
          Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
      if (processorArch.contains('ARM64')) {
        arch = 'arm64';
      } else {
        arch = 'x64';
      }
    } else {
      // Linux: 通过 uname -m 或环境变量
      if (version.contains('arm64') || version.contains('aarch64')) {
        arch = 'arm64';
      } else {
        arch = 'x64';
      }
    }

    return '$arch-$os';
  }

  /// 检测是否为 Apple Silicon Mac。
  static bool _isAppleSilicon() {
    // 环境变量:运行在 Rosetta 下的 x86_64 二进制,宿主为 Apple Silicon
    final sysctl = Platform.environment['SYSCTL_PROC_TRANSLATED'];
    if (sysctl == '1') return true;

    // 首选:同步执行 `uname -m` 读取内核架构
    try {
      final result = Process.runSync('uname', <String>['-m']);
      if (result.exitCode == 0) {
        final machine = '${result.stdout}'.trim().toLowerCase();
        if (machine == 'arm64' || machine == 'aarch64') return true;
        if (machine == 'x86_64' || machine == 'i386') return false;
      }
    } catch (_) {
      // uname 不可用时回退到路径探测
    }

    // 回退:Homebrew 在 Apple Silicon 上默认安装到 /opt/homebrew
    return Directory('/opt/homebrew/bin').existsSync();
  }

  /// 获取应用内嵌入的 ripgrep 路径。
  ///
  /// 查找优先级：
  /// 1. 开发模式：项目根目录的 vendor/ripgrep
  /// 2. macOS 打包：应用包内的 Resources/vendor/ripgrep
  /// 3. Windows 打包：可执行文件同级的 vendor/ripgrep
  static Future<String?> _getEmbeddedRipgrepPath() async {
    final platformDir = _getRipgrepPlatformDir();
    final rgName = Platform.isWindows ? 'rg.exe' : 'rg';

    // 候选路径列表
    final candidates = <String>[];

    final executablePath = Platform.resolvedExecutable;
    final executableDir = p.dirname(executablePath);

    if (Platform.isMacOS) {
      // macOS 打包后：MyApp.app/Contents/MacOS/MyApp
      // vendor 应该在：MyApp.app/Contents/Resources/vendor
      final appBundle = p.dirname(executableDir); // Contents
      final resourcesDir = p.join(
        appBundle,
        'Resources',
        'vendor',
        'ripgrep',
        platformDir,
        rgName,
      );
      candidates.add(resourcesDir);

      // 开发模式：直接使用项目目录
      // 项目结构：OpenHand/vendor/ripgrep/...
      // 可执行文件在：OpenHand/build/macos/Build/Products/Debug/openhand.app/...
      final projectRoot = _findProjectRoot(executableDir);
      if (projectRoot != null) {
        candidates.add(
          p.join(projectRoot, 'vendor', 'ripgrep', platformDir, rgName),
        );
      }
    } else if (Platform.isWindows) {
      // Windows 打包后：安装目录/MyApp.exe
      // vendor 应该在：安装目录/vendor/ripgrep
      candidates.add(
        p.join(executableDir, 'vendor', 'ripgrep', platformDir, rgName),
      );

      // 开发模式
      final projectRoot = _findProjectRoot(executableDir);
      if (projectRoot != null) {
        candidates.add(
          p.join(projectRoot, 'vendor', 'ripgrep', platformDir, rgName),
        );
      }
    } else if (Platform.isLinux) {
      // Linux 类似 Windows
      candidates.add(
        p.join(executableDir, 'vendor', 'ripgrep', platformDir, rgName),
      );

      final projectRoot = _findProjectRoot(executableDir);
      if (projectRoot != null) {
        candidates.add(
          p.join(projectRoot, 'vendor', 'ripgrep', platformDir, rgName),
        );
      }
    }

    // 添加当前工作目录作为最后备选（开发模式）
    candidates.add(
      p.join(Directory.current.path, 'vendor', 'ripgrep', platformDir, rgName),
    );

    // 检查每个候选路径
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        // 确保有执行权限（非 Windows）
        if (!Platform.isWindows) {
          try {
            final stat = await file.stat();
            // 检查是否有执行权限 (mode & 0x49 = owner/group/other execute)
            if (stat.mode & 0x49 == 0) {
              // 尝试添加执行权限
              await Process.run('chmod', <String>['+x', candidate]);
            }
          } catch (_) {
            // 忽略权限检查失败
          }
        }
        return candidate;
      }
    }

    return null;
  }

  /// 查找项目根目录（通过向上查找 pubspec.yaml）。
  static String? _findProjectRoot(String startDir) {
    var current = startDir;
    for (var i = 0; i < 10; i++) {
      final pubspec = File(p.join(current, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        return current;
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    return null;
  }

  /// rg 系统安装常见路径（macOS/Linux）。
  static const List<String> _rgSystemPaths = <String>[
    '/opt/homebrew/bin/rg', // macOS Apple Silicon (Homebrew)
    '/usr/local/bin/rg', // macOS Intel (Homebrew) / Linux
    '/usr/bin/rg', // Linux system install
    '/home/linuxbrew/.linuxbrew/bin/rg', // Linux Homebrew
  ];

  /// 解析 rg (ripgrep) 可执行文件路径。
  ///
  /// 查找优先级：
  /// 1. **应用内嵌入的 rg**（确保无需用户预装）
  /// 2. PATH 环境变量（通过 which 命令）
  /// 3. 常见系统安装路径
  /// 4. macOS 登录 shell 环境
  ///
  /// 返回 null 表示未找到 ripgrep。
  static Future<String?> resolveRipgrepPath() async {
    if (_cachedRgPath != null) return _cachedRgPath;

    // 1. 优先使用应用内嵌入的 rg
    final embeddedPath = await _getEmbeddedRipgrepPath();
    if (embeddedPath != null) {
      _cachedRgPath = embeddedPath;
      return _cachedRgPath;
    }

    // 2. 尝试从 PATH 环境变量查找（通过 which/where 命令）
    try {
      final whichCmd = Platform.isWindows ? 'where' : 'which';
      final whichResult = await Process.run(whichCmd, <String>['rg']);
      if (whichResult.exitCode == 0) {
        final foundPath = whichResult.stdout
            .toString()
            .trim()
            .split('\n')
            .first;
        if (foundPath.isNotEmpty && await File(foundPath).exists()) {
          _cachedRgPath = foundPath;
          return _cachedRgPath;
        }
      }
    } catch (_) {
      // which/where 命令失败，继续尝试其他方式
    }

    // 3. 直接检查常见系统安装路径（非 Windows）
    if (!Platform.isWindows) {
      for (final candidatePath in _rgSystemPaths) {
        if (await File(candidatePath).exists()) {
          _cachedRgPath = candidatePath;
          return _cachedRgPath;
        }
      }
    }

    // 4. 尝试从登录 shell 获取环境变量（macOS）
    if (Platform.isMacOS) {
      try {
        final shellResult = await Process.run(
          '/bin/zsh',
          <String>['-l', '-c', 'which rg'],
          environment: <String, String>{
            'HOME': Platform.environment['HOME'] ?? '',
          },
        );
        if (shellResult.exitCode == 0) {
          final foundPath = shellResult.stdout.toString().trim();
          if (foundPath.isNotEmpty && await File(foundPath).exists()) {
            _cachedRgPath = foundPath;
            return _cachedRgPath;
          }
        }
      } catch (_) {
        // 登录 shell 查找失败
      }
    }

    return null;
  }

  /// 检查 ripgrep 是否可用。
  static Future<bool> isRipgrepAvailable() async {
    return await resolveRipgrepPath() != null;
  }

  /// 清除缓存的 ripgrep 路径（供测试使用）。
  static void clearRipgrepPathCache() {
    _cachedRgPath = null;
  }

  /// 执行进程，正确处理异常并返回统一的 ProcessResult。
  ///
  /// [workingDirectory]：工作目录。如果为空，使用当前目录。
  /// [inheritEnvironment]：是否继承父进程的环境变量。默认 true。
  static Future<ProcessResult> runProcessSafely(
    String executable,
    List<String> args, {
    String? workingDirectory,
    bool inheritEnvironment = true,
  }) async {
    try {
      return await Process.run(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: inheritEnvironment ? Platform.environment : null,
      );
    } on ProcessException catch (error) {
      return ProcessResult(
        0,
        127,
        '',
        'Process execution failed: ${error.message}',
      );
    } on FileSystemException catch (error) {
      return ProcessResult(0, 126, '', 'File system error: ${error.message}');
    } catch (error) {
      return ProcessResult(0, 1, '', 'Unexpected error: $error');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 2026-04-13 写操作权限确认支持
  // ══════════════════════════════════════════════════════════════════════════

  /// 写操作权限确认默认超时时间（5分钟）。
  /// 2026-04-29 — Group B: 调用方可传 [timeoutMs] 覆盖默认值。
  static const int _writeConfirmationTimeoutMs = 300000;

  static Map<String, Object?> _writeConfirmationMetadata(
    Map<String, Object?> metadata,
    BashCommandApprovalDecision decision, {
    bool missingCallback = false,
  }) {
    return bashWriteConfirmationMetadata(
      metadata,
      decision,
      missingCallback: missingCallback,
    );
  }

  /// 请求用户确认写操作。
  ///
  /// 当 [requireWriteConfirmation] 为 true 且 [confirmWriteCommand] 回调存在时，
  /// 会向用户请求写操作审批。
  ///
  /// 如果用户批准或不需要确认，返回 null。
  /// 如果用户拒绝、超时或取消，返回相应的错误结果。
  static Future<AiToolExecutionResult?> requestWriteConfirmation({
    required String toolName,
    required String operationDescription,
    required String targetPath,
    required bool requireWriteConfirmation,
    required Future<BashCommandApprovalDecision> Function(
      BashCommandApprovalRequest request,
    )?
    confirmWriteCommand,
    Future<void>? cancelSignal,
    int? timeoutMs,
    String? approvalCommand,
    String? approvalWorkingDirectory,
    String? resultCommand,
    String? writeAnalysisReason,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    // 如果不需要写确认，直接通过
    if (!requireWriteConfirmation) {
      return null;
    }

    // 如果需要确认但没有确认回调，这是一个配置错误，拒绝执行
    if (confirmWriteCommand == null) {
      final workingDirectory =
          approvalWorkingDirectory ?? p.dirname(targetPath);
      final commandForResult = resultCommand ?? '$toolName $targetPath';
      return rejectedWriteResult(
        toolName: toolName,
        targetPath: targetPath,
        reason: '需要写操作确认但未提供确认回调，操作已拒绝执行。',
        command: commandForResult,
        workingDirectory: workingDirectory,
        writeAnalysisReason: writeAnalysisReason,
        metadata: _writeConfirmationMetadata(
          metadata,
          BashCommandApprovalDecision.rejected,
          missingCallback: true,
        ),
      );
    }

    final workingDirectory = approvalWorkingDirectory ?? p.dirname(targetPath);
    final commandForApproval =
        approvalCommand ?? '$toolName $targetPath\n$operationDescription';
    final commandForResult = resultCommand ?? '$toolName $targetPath';
    final request = BashCommandApprovalRequest(
      command: commandForApproval,
      workingDirectory: workingDirectory,
      isWriteCommand: true,
    );

    late final _WriteConfirmationOutcome outcome;
    try {
      final approvalFuture = confirmWriteCommand(request)
          .timeout(
            Duration(milliseconds: timeoutMs ?? _writeConfirmationTimeoutMs),
          )
          .then<_WriteConfirmationOutcome>(
            (decision) => _WriteConfirmationOutcome.fromDecision(decision),
          );

      if (cancelSignal == null) {
        outcome = await approvalFuture;
      } else {
        outcome = await Future.any<_WriteConfirmationOutcome>([
          approvalFuture,
          cancelSignal.then(
            (_) => const _WriteConfirmationOutcome.fromDecision(
              BashCommandApprovalDecision.cancelled,
            ),
          ),
        ]);
      }
    } on TimeoutException {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.timedOut,
        command: commandForResult,
        workingDirectory: workingDirectory,
        stdout: '',
        stderr: '写操作确认超时（用户既未批准也未明确拒绝）。本次工具调用未执行；如仍需该副作用请重新征询用户意图后再次尝试。',
        durationMs: 0,
        resultText:
            'status: timed_out\nreason: Write confirmation timed out — user did not respond.',
        isWriteCommand: true,
        writeAnalysisReason:
            writeAnalysisReason ??
            'builtin file mutation tool requires confirmation',
        metadata: _writeConfirmationMetadata(
          metadata,
          BashCommandApprovalDecision.timedOut,
        ),
      );
    }

    switch (outcome.decision) {
      case BashCommandApprovalDecision.approved:
        return null;
      case BashCommandApprovalDecision.rejected:
        return rejectedWriteResult(
          toolName: toolName,
          targetPath: targetPath,
          reason: '用户已显式拒绝该写操作确认（点击"取消"按钮）。请勿重试该写操作；先与用户确认期望后再行动。',
          command: commandForResult,
          workingDirectory: workingDirectory,
          writeAnalysisReason: writeAnalysisReason,
          metadata: _writeConfirmationMetadata(
            metadata,
            BashCommandApprovalDecision.rejected,
          ),
        );
      case BashCommandApprovalDecision.dismissed:
        return rejectedWriteResult(
          toolName: toolName,
          targetPath: targetPath,
          reason:
              '用户按 Esc / 关闭了写操作确认弹窗，未明确表态。视为"决策悬置"：本次工具调用未执行；与用户确认意图后再决定下一步。',
          command: commandForResult,
          workingDirectory: workingDirectory,
          writeAnalysisReason: writeAnalysisReason,
          metadata: _writeConfirmationMetadata(
            metadata,
            BashCommandApprovalDecision.dismissed,
          ),
        );
      case BashCommandApprovalDecision.timedOut:
        return AiToolExecutionResult(
          status: BashToolExecutionStatus.timedOut,
          command: commandForResult,
          workingDirectory: workingDirectory,
          stdout: '',
          stderr: '写操作确认弹窗超时（用户既未批准也未明确拒绝）。本次工具调用未执行。',
          durationMs: 0,
          resultText:
              'status: timed_out\nreason: Write confirmation timed out — user did not respond.',
          isWriteCommand: true,
          writeAnalysisReason:
              writeAnalysisReason ??
              'builtin file mutation tool requires confirmation',
          metadata: _writeConfirmationMetadata(
            metadata,
            BashCommandApprovalDecision.timedOut,
          ),
        );
      case BashCommandApprovalDecision.cancelled:
        return AiToolExecutionResult(
          status: BashToolExecutionStatus.cancelled,
          command: commandForResult,
          workingDirectory: workingDirectory,
          stdout: '',
          stderr: '写操作确认在用户表态前被取消。本次工具调用未执行，后续不要假定文件已被修改。',
          durationMs: 0,
          resultText:
              'status: cancelled\nreason: Write confirmation was cancelled before a decision.',
          isWriteCommand: true,
          writeAnalysisReason:
              writeAnalysisReason ??
              'builtin file mutation tool requires confirmation',
          metadata: _writeConfirmationMetadata(
            metadata,
            BashCommandApprovalDecision.cancelled,
          ),
        );
    }
  }

  /// 生成写操作被拒绝的结果。
  static AiToolExecutionResult rejectedWriteResult({
    required String toolName,
    required String targetPath,
    required String reason,
    String? command,
    String? workingDirectory,
    String? writeAnalysisReason,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.rejected,
      command: command ?? '$toolName $targetPath',
      workingDirectory: workingDirectory ?? p.dirname(targetPath),
      stdout: '',
      stderr: reason,
      durationMs: 0,
      resultText: 'status: rejected\nreason: $reason',
      isWriteCommand: true,
      writeAnalysisReason:
          writeAnalysisReason ??
          'builtin file mutation tool requires confirmation',
      metadata: metadata,
    );
  }
}

/// 2026-04-13 写确认结果内部类型。
class _WriteConfirmationOutcome {
  const _WriteConfirmationOutcome.fromDecision(this.decision);

  final BashCommandApprovalDecision decision;

  bool get approved => decision == BashCommandApprovalDecision.approved;
  bool get cancelled => decision == BashCommandApprovalDecision.cancelled;
}

class AiEditableTextSnapshot {
  const AiEditableTextSnapshot({
    required this.rawContent,
    required this.normalizedContent,
    required this.lineEnding,
  });

  factory AiEditableTextSnapshot.fromRaw(String rawContent) {
    return AiEditableTextSnapshot(
      rawContent: rawContent,
      normalizedContent: AiToolUtils.normalizeTextLineEndings(rawContent),
      lineEnding: _detectLineEnding(rawContent),
    );
  }

  factory AiEditableTextSnapshot.empty() {
    return const AiEditableTextSnapshot(
      rawContent: '',
      normalizedContent: '',
      lineEnding: '\n',
    );
  }

  final String rawContent;
  final String normalizedContent;
  final String lineEnding;

  String restoreLineEndings(String normalizedValue) {
    if (lineEnding == '\n') return normalizedValue;
    return normalizedValue.replaceAll('\n', lineEnding);
  }

  static String _detectLineEnding(String value) {
    if (value.contains('\r\n')) return '\r\n';
    if (value.contains('\r')) return '\r';
    return '\n';
  }
}

class AiEditableTextFileTooLargeException implements Exception {
  const AiEditableTextFileTooLargeException({
    required this.filePath,
    required this.sizeBytes,
    required this.limitBytes,
  });

  final String filePath;
  final int sizeBytes;
  final int limitBytes;

  String get message =>
      'File is too large to edit (${formatByteSize(sizeBytes)}). '
      'Maximum editable text file size is ${formatByteSize(limitBytes)}: '
      '$filePath';

  @override
  String toString() => message;
}

class ReplacementResult {
  const ReplacementResult.success(
    this.content, {
    this.appliedNewString = '',
    this.matchedOldString = '',
    this.replacementCount = 1,
  }) : success = true,
       errorMessage = '';

  const ReplacementResult.failure(this.errorMessage)
    : success = false,
      content = '',
      appliedNewString = '',
      matchedOldString = '',
      replacementCount = 0;

  final bool success;
  final String content;
  final String errorMessage;
  final String appliedNewString;
  final String matchedOldString;
  final int replacementCount;
}
