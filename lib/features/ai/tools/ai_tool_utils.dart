import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/path_safety.dart';
import '../../../shared/util/reader_file_type.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_normalization.dart';
import '../service/bash/ai_bash_tool_service.dart';
import '../service/fs/ai_file_history_service.dart';
import '../service/fs/ai_file_mutation_ledger.dart';
import '../service/fs/ai_file_tracker_service.dart';
import '../service/runtime/ai_tool_runtime_service.dart';
import 'ai_tool_execution_context.dart';

class AiToolUtils {
  AiToolUtils._();

  static const int maxFileCharacters = 64000;
  static const int maxReadBytes = maxFileCharacters * 4;
  static const int maxSearchOutputCharacters = 24000;
  static const int maxReadLineLength = 2000;
  static const int defaultReadLimit = 2000;
  static const int maxReadLimit = 20000;
  static const int maxBinaryPreviewBytes = 32;

  /// 二进制探测所需的前缀字节数。[looksBinary] 只检查前 2048 字节，
  /// [maxBinaryPreviewBytes] 的十六进制预览只用前 32 字节，因此读取更多
  /// 纯属浪费磁盘 IO 与内存拷贝。
  static const int binarySniffBytes = 2048;
  static const int maxStructuredReadBytes = 16 * kBytesPerMiB;
  static const int maxLedgerCaptureBytes = 16 * kBytesPerMiB;
  static const int maxEditableTextFileBytes = 128 * kBytesPerMiB;
  static const int maxGeneratedTextPayloadCharacters = 10 * kBytesPerMiB;
  static const int maxMissingPathSuggestionScanEntries = 256;
  static const int maxFileTreeScanEntries = 100000;
  static const Duration fileTreeScanIdleTimeout = Duration(seconds: 3);
  static const Duration fileTreeScanTotalTimeout = Duration(seconds: 10);
  static const Duration _metadataProcessTimeout = Duration(seconds: 2);
  static const Duration _searchProcessTimeout = Duration(seconds: 30);

  static int _safeWriteArtifactCounter = 0;
  static final Map<String, Future<void>> _fileMutationLocks =
      <String, Future<void>>{};

  static String defaultWorkingDirectory() {
    return p.normalize(Directory.current.path);
  }

  static String resolvePath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty) return defaultWorkingDirectory();
    if (p.isAbsolute(normalizedInput)) return p.normalize(normalizedInput);
    return p.normalize(p.join(defaultWorkingDirectory(), normalizedInput));
  }

  static String readString(Object? value, {String fallback = ''}) {
    return optionalStringFromValue(value) ??
        (optionalStringFromValue(fallback) ?? '');
  }

  static String readFirstString(
    Map<String, Object?> values,
    Iterable<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = optionalStringFromValue(values[key]);
      if (value != null) return value;
    }
    return readString(fallback);
  }

  static Future<String> missingPathMessage({
    required String subject,
    required String path,
  }) async {
    final base = '$subject does not exist: $path';
    final suggestion = await suggestSiblingPath(path);
    if (suggestion == null) return base;
    return '$base Did you mean $suggestion?';
  }

  static Future<String?> suggestSiblingPath(String missingPath) async {
    final normalizedMissingPath = p.normalize(missingPath);
    final parentPath = p.dirname(normalizedMissingPath);
    final parent = Directory(parentPath);
    final deadline = MonotonicDeadline(
      fileTreeScanTotalTimeout,
      timeoutMessage: '同级候选路径扫描超时。',
    );

    try {
      if (!await parent.exists().timeout(
        deadline.limit(fileTreeScanIdleTimeout),
      )) {
        return null;
      }
      final targetName = p.basename(normalizedMissingPath);
      final targetNameLower = targetName.toLowerCase();
      final targetBaseLower = p
          .basenameWithoutExtension(targetName)
          .toLowerCase();
      final targetExtensionLower = p.extension(targetName).toLowerCase();
      _MissingPathSuggestion? best;
      final remainingTime = deadline.remaining();
      final listing = await listDirectoryBounded(
        parent,
        maxEntries: maxMissingPathSuggestionScanEntries,
        idleTimeout: deadline.limit(fileTreeScanIdleTimeout),
        totalTimeout: remainingTime,
      );
      for (final entity in listing.entries) {
        final candidatePath = p.normalize(entity.path);
        if (candidatePath == normalizedMissingPath) continue;
        final type = await FileSystemEntity.type(
          candidatePath,
          followLinks: false,
        ).timeout(deadline.limit(fileTreeScanIdleTimeout));
        if (type == FileSystemEntityType.directory ||
            type == FileSystemEntityType.notFound) {
          continue;
        }
        final candidateName = p.basename(candidatePath);
        final score = _missingPathSuggestionScore(
          targetNameLower: targetNameLower,
          targetBaseLower: targetBaseLower,
          targetExtensionLower: targetExtensionLower,
          candidateNameLower: candidateName.toLowerCase(),
          candidateBaseLower: p
              .basenameWithoutExtension(candidateName)
              .toLowerCase(),
          candidateExtensionLower: p.extension(candidateName).toLowerCase(),
        );
        if (score == null) continue;
        final candidate = _MissingPathSuggestion(
          path: candidatePath,
          name: candidateName.toLowerCase(),
          score: score,
        );
        if (best == null || candidate.isBetterThan(best)) {
          best = candidate;
        }
      }
      return best?.path;
    } catch (error, stack) {
      silentLog('ai_tool_utils', '查找缺失文件的同级候选路径', error, stack);
      return null;
    } finally {
      deadline.stop();
    }
  }

  static int? _missingPathSuggestionScore({
    required String targetNameLower,
    required String targetBaseLower,
    required String targetExtensionLower,
    required String candidateNameLower,
    required String candidateBaseLower,
    required String candidateExtensionLower,
  }) {
    if (candidateNameLower == targetNameLower) return 100000;
    if (targetBaseLower.isNotEmpty && candidateBaseLower == targetBaseLower) {
      return 90000;
    }

    final sameExtension =
        targetExtensionLower.isNotEmpty &&
        candidateExtensionLower == targetExtensionLower;
    if (sameExtension && targetBaseLower.isNotEmpty) {
      final lengthPenalty = (candidateBaseLower.length - targetBaseLower.length)
          .abs();
      if (candidateBaseLower.startsWith(targetBaseLower)) {
        return 80000 - lengthPenalty;
      }
      if (targetBaseLower.startsWith(candidateBaseLower)) {
        return 78000 - lengthPenalty;
      }
      if (candidateBaseLower.contains(targetBaseLower) ||
          targetBaseLower.contains(candidateBaseLower)) {
        return 70000 - lengthPenalty;
      }
      final maxDistance = targetBaseLower.length <= 8 ? 2 : 3;
      final editDistance = _boundedEditDistance(
        targetBaseLower,
        candidateBaseLower,
        maxDistance,
      );
      if (editDistance != null) {
        return 65000 - (editDistance * 100) - lengthPenalty;
      }
    }

    if (targetBaseLower.isNotEmpty &&
        candidateBaseLower.startsWith(targetBaseLower)) {
      return 50000 - (candidateBaseLower.length - targetBaseLower.length);
    }
    return null;
  }

  static int? _boundedEditDistance(String a, String b, int maxDistance) {
    if ((a.length - b.length).abs() > maxDistance) return null;
    if (a == b) return 0;
    if (a.isEmpty) return b.length <= maxDistance ? b.length : null;
    if (b.isEmpty) return a.length <= maxDistance ? a.length : null;

    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 1; i <= a.length; i += 1) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      var rowMin = current[0];
      for (var j = 1; j <= b.length; j += 1) {
        final substitutionCost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
            ? 0
            : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + substitutionCost;
        final value = deletion < insertion
            ? (deletion < substitution ? deletion : substitution)
            : (insertion < substitution ? insertion : substitution);
        current[j] = value;
        if (value < rowMin) rowMin = value;
      }
      if (rowMin > maxDistance) return null;
      previous = current;
    }
    final distance = previous[b.length];
    return distance <= maxDistance ? distance : null;
  }

  static bool isNotebookPath(String filePath) {
    return p.extension(filePath).toLowerCase() == '.ipynb';
  }

  static AiToolExecutionResult? validateNotebookTextMutation({
    required String toolName,
    required String filePath,
  }) {
    if (!isNotebookPath(filePath)) return null;
    return invalidResult(
      toolName,
      '$toolName cannot edit Jupyter Notebook files directly. Use NotebookEdit for .ipynb cell changes.',
    );
  }

  static Map<String, Object?> decodeArguments(
    String rawArguments, {
    Map<String, Object?>? parameters,
  }) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map) {
        return _coerceArgumentMap(
          stringKeyedMapFromValue(decoded),
          parameters: parameters,
        );
      }
    } catch (error, stack) {
      silentLog('ai_tool_utils', '解析工具参数 JSON', error, stack);
    }
    return const <String, Object?>{};
  }

  /// 修正常见的模型参数嵌套错误，使下游工具首次调用即可收到符合结构的参数：
  ///
  ///   1. `{"_raw": "<query>foo</query>"}`
  ///         → 解析 XML/CDATA 并提升为顶层键，如 `{query: "foo"}`。
  ///   2. `{"todos": {"item": [...]}}`
  ///         → 将单键 XML 数组包装展平为普通列表，如 `{todos: [...]}`。
  ///   3. `{"query": "<![CDATA[foo]]>"}`
  ///         → 移除字符串值的 CDATA 包装。
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
    // 合并 `_raw` 中的键，但不覆盖显式参数。
    for (final entry in rawExtracted.entries) {
      result.putIfAbsent(entry.key, () => entry.value);
    }
    // 部分模型会生成 `{key: {key: [...]}}`，仅展开这一层重复包装。
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
      // 仅在结构要求数组或对象时解析 JSON 字符串，避免改写文件正文。
      final trimmed = stripped.trim();
      final schemaType = _schemaType(schema);
      if (schemaType == 'array' || schemaType == 'object') {
        final decoded = tryDecodeJson(trimmed);
        if (decoded != null) {
          return _coerceArgumentValue(decoded, schema: schema);
        }
      }
      if (schemaType == 'integer' || schemaType == 'number') {
        final decoded = tryDecodeJson(trimmed);
        if (decoded is num) return decoded;
        final parsed = num.tryParse(trimmed);
        if (parsed != null) return parsed;
      }
      if (schemaType == 'boolean') {
        final decoded = tryDecodeJson(trimmed);
        if (decoded is bool) return decoded;
        return optionalBoolFromValue(trimmed) ?? stripped;
      }
      return stripped;
    }
    if (value is Map) {
      final asMap = stringKeyedMapFromValue(value);
      // 展平单键 XML 数组包装：`{item:[...]}` → `[...]`。
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
      if (value is Map) result[key] = stringKeyedMapFromValue(value);
    }
    return result;
  }

  static Map<String, Object?>? _itemSchema(Map<String, Object?>? schema) {
    final items = schema?['items'];
    if (items is Map) return stringKeyedMapFromValue(items);
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

  static String _stripCdata(String value) {
    final cdataPattern = RegExp(
      r'<!\[CDATA\[([\s\S]*?)\]\]>',
      caseSensitive: false,
    );
    if (!cdataPattern.hasMatch(value)) return value;
    return value.replaceAllMapped(cdataPattern, (m) => m.group(1) ?? '');
  }

  /// 从自由格式 XML 中提取键值并移除 CDATA；闭合标签不匹配时读取到下一闭合标签。
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

  static int? readInt(Object? value) {
    return optionalIntegralIntFromValue(value);
  }

  static int readClampedInt(
    Object? value, {
    required int fallback,
    required int min,
    required int max,
  }) {
    return clampedIntegralIntFromValue(
      value,
      fallback: fallback,
      min: min,
      max: max,
    );
  }

  static bool? readBool(Object? value) {
    return optionalBoolFromValue(value);
  }

  static List<Object?>? readList(Object? value) {
    if (value is List<Object?>) return value;
    if (value is List) return value.cast<Object?>().toList(growable: false);
    if (value is String) {
      final decoded = tryDecodeJson(value.trim());
      if (decoded is List) {
        return decoded.cast<Object?>().toList(growable: false);
      }
    }
    return null;
  }

  static List<String> normalizeStringList(Object? value) {
    return stringListFromValueOrJsonText(value)
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String truncateContent(String content, int maxCharacters) {
    return clipText(content, maxCharacters);
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
    final withoutTags = stripHtmlTags(withoutScripts);
    final withoutEntities = withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return collapseInlineWhitespace(withoutEntities);
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
    try {
      final rawContent = await readBoundedFileString(
        file,
        maxBytes: maxEditableTextFileBytes,
      );
      return AiEditableTextSnapshot.fromRaw(rawContent);
    } on BoundedFileReadException catch (error) {
      if (error.failure != BoundedFileReadFailure.tooLarge) rethrow;
      var sizeBytes = maxEditableTextFileBytes + 1;
      try {
        final currentSize = await file.length();
        if (currentSize > maxEditableTextFileBytes) sizeBytes = currentSize;
      } on FileSystemException {
        // 保留有界读取产生的确定性大小超限错误。
      }
      throw AiEditableTextFileTooLargeException(
        filePath: file.path,
        sizeBytes: sizeBytes,
        limitBytes: maxEditableTextFileBytes,
      );
    }
  }

  static String normalizeTextLineEndings(String value) {
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static AiToolExecutionResult invalidResult(
    String command,
    String message, {
    String stdout = '',
    int durationMs = 0,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.invalidArguments,
      command: command,
      workingDirectory: defaultWorkingDirectory(),
      stdout: stdout,
      stderr: message,
      durationMs: durationMs,
      resultText: 'status: invalid_arguments\nerror: $message',
      metadata: metadata,
    );
  }

  static AiToolExecutionResult? validateGeneratedTextPayloadSize({
    required String toolName,
    required String fieldName,
    required String value,
  }) {
    if (value.length <= maxGeneratedTextPayloadCharacters) return null;
    return invalidResult(
      toolName,
      '$fieldName exceeds the maximum allowed size '
      '(${value.length} chars, limit $maxGeneratedTextPayloadCharacters). '
      'Split the generated content into smaller edits or files.',
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
    return result.copyWith(
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

    // 脏写检测 - 检查文件是否在读取后被外部修改
    if (fileTracker != null) {
      final dirtyWriteError = await fileTracker.validateSafeToWrite(filePath);
      if (dirtyWriteError != null) {
        return invalidResult(toolName, dirtyWriteError);
      }
    }

    return null;
  }

  static Future<AiFileMutationPreparation> prepareFileMutation({
    required AiToolExecutionContext context,
    required String toolName,
    required String operationDescription,
    required String filePath,
    required bool fileExists,
  }) async {
    final confirmationResult = await requestWriteConfirmation(
      toolName: toolName,
      operationDescription: operationDescription,
      targetPath: filePath,
      requireWriteConfirmation: context.requireWriteCommandConfirmation,
      confirmWriteCommand: context.confirmWriteCommand,
      cancelSignal: context.cancelSignal,
      timeoutMs: context.metadata['write_confirmation_timeout_ms'] as int?,
    );
    if (confirmationResult != null) {
      return AiFileMutationPreparation(error: confirmationResult);
    }

    final fileTracker =
        context.metadata['file_tracker'] as AiFileTrackerService?;
    final readValidation = await validateReadBeforeMutation(
      toolName: toolName,
      filePath: filePath,
      previouslyReadFiles: context.previouslyReadFiles,
      requireExistingFileRead: fileExists,
      fileTracker: fileTracker,
    );
    if (readValidation != null) {
      return AiFileMutationPreparation(error: readValidation);
    }

    String? versionId;
    String? beforeContent;
    if (fileExists) {
      versionId = await saveFileVersionBeforeMutation(
        filePath: filePath,
        sessionId: context.sessionId,
        toolCallId: context.toolCall.id,
        fileHistory: context.metadata['file_history'] as AiFileHistoryService?,
      );
      beforeContent = await readFileContentForLedger(filePath);
    }
    return AiFileMutationPreparation(
      fileTracker: fileTracker,
      historyVersionId: versionId,
      beforeContent: beforeContent,
    );
  }

  /// 在文件修改前保存历史版本
  ///
  /// 实现 OpenCode 历史版本机制
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
  /// 写入成功后更新 lastReadTime
  static Future<void> updateTrackerAfterMutation({
    required String filePath,
    AiFileTrackerService? fileTracker,
  }) async {
    if (fileTracker == null) return;
    await fileTracker.updateAfterWrite(filePath);
  }

  /// 把一次工具产生的文件级变动写入新的 [AiFileMutationLedger]，
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
      return await readBoundedFileString(f, maxBytes: maxLedgerCaptureBytes);
    } catch (error, stack) {
      silentLog('ai_tool_utils', '读取文件变更账本快照', error, stack);
      return null;
    }
  }

  static Future<void> writeTextFileSafely(File file, String content) async {
    await _runWithFileMutationLock(
      file,
      () => _writeTextFileSafelyUnlocked(file, content),
    );
  }

  static Future<void> _writeTextFileSafelyUnlocked(
    File file,
    String content,
  ) async {
    final entityType = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.directory) {
      throw FileSystemException(
        'Refusing to write text content to a directory.',
        file.path,
      );
    }
    await file.parent.create(recursive: true);
    if (entityType == FileSystemEntityType.link) {
      await file.writeAsString(content, flush: true);
      return;
    }
    final tempFile = await _uniqueSafeWriteArtifact(file, 'tmp');
    await tempFile.writeAsString(content, flush: true);
    if (await file.exists()) await _copyExistingFileMode(file, tempFile);
    try {
      await tempFile.rename(file.path);
    } on FileSystemException {
      if (!await tempFile.exists()) rethrow;
      await _replaceTextFileWithTemporaryBackup(file, tempFile);
    } catch (_) {
      await _deleteFileIfExistsBestEffort(tempFile, '清理安全写入临时文件');
      rethrow;
    }
  }

  /// 写入前执行最终读取校验，避免确认或历史记录流程形成过期写入窗口。
  static Future<AiToolExecutionResult?> writeTextFileWithMutationGuard({
    required String toolName,
    required File file,
    required String content,
    required Set<String> previouslyReadFiles,
    required bool requireExistingFileRead,
    AiFileTrackerService? fileTracker,
  }) async {
    return _runWithFileMutationLock(file, () async {
      final entityType = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      if (entityType == FileSystemEntityType.directory) {
        return invalidResult(
          toolName,
          '$toolName refuses to write text content to a directory: ${file.path}',
        );
      }
      if (!requireExistingFileRead &&
          entityType != FileSystemEntityType.notFound) {
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

      await _writeTextFileSafelyUnlocked(file, content);
      await updateTrackerAfterMutation(
        filePath: file.path,
        fileTracker: fileTracker,
      );
      return null;
    });
  }

  static Future<AiToolExecutionResult?> verifyTextFileWrite({
    required String toolName,
    required File file,
    required String expectedContent,
  }) async {
    final String actualContent;
    try {
      final expectedBytes = utf8.encode(expectedContent).length;
      actualContent = await readBoundedFileString(
        file,
        maxBytes: expectedBytes == 0 ? 1 : expectedBytes,
      );
    } catch (error) {
      return invalidResult(
        toolName,
        'File was written but verification read failed: $error',
      );
    }
    if (actualContent == expectedContent) return null;
    return invalidResult(
      toolName,
      'File was written but verification failed: expected '
      '${expectedContent.length} characters, read back '
      '${actualContent.length}. This may indicate a permission issue or '
      'concurrent modification.',
    );
  }

  static Future<T> _runWithFileMutationLock<T>(
    File file,
    Future<T> Function() operation,
  ) async {
    final key = await _fileMutationLockKey(file);
    final previous = _fileMutationLocks[key] ?? Future<void>.value();
    final gate = Completer<void>();
    final gateFuture = gate.future;
    _fileMutationLocks[key] = gateFuture;
    try {
      await previous.catchError((Object _, StackTrace _) {});
      return await operation();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_fileMutationLocks[key], gateFuture)) {
        _fileMutationLocks.remove(key);
      }
    }
  }

  static Future<String> _fileMutationLockKey(File file) async {
    final rawPath = p.normalize(file.absolute.path);
    try {
      final entityType = await FileSystemEntity.type(
        rawPath,
        followLinks: false,
      );
      if (entityType != FileSystemEntityType.link) return rawPath;
      final linkTarget = await Link(rawPath).target();
      final resolved = p.isAbsolute(linkTarget)
          ? linkTarget
          : p.join(p.dirname(rawPath), linkTarget);
      return p.normalize(resolved);
    } on FileSystemException {
      return rawPath;
    }
  }

  static Future<File> _uniqueSafeWriteArtifact(
    File targetFile,
    String role,
  ) async {
    for (var attempt = 0; attempt < 16; attempt++) {
      final counter = _safeWriteArtifactCounter =
          (_safeWriteArtifactCounter + 1) & 0x3fffffff;
      final path = p.join(
        targetFile.parent.path,
        '.${p.basename(targetFile.path)}.'
        '${DateTime.now().microsecondsSinceEpoch}.$counter.$role',
      );
      final candidate = File(path);
      final type = await FileSystemEntity.type(
        path,
        followLinks: false,
      ).timeout(defaultBoundedFileReadIdleTimeout);
      if (type == FileSystemEntityType.notFound) {
        return candidate;
      }
    }
    throw FileSystemException(
      'Unable to allocate a unique temporary write artifact.',
      targetFile.path,
    );
  }

  static Future<void> _deleteFileIfExistsBestEffort(
    File file,
    String where,
  ) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error, stack) {
      silentLog('ai_tool_utils', where, error, stack);
    }
  }

  static Future<void> _replaceTextFileWithTemporaryBackup(
    File targetFile,
    File tempFile,
  ) async {
    File? backupFile;
    var movedExistingFile = false;
    try {
      if (await targetFile.exists()) {
        backupFile = await _uniqueSafeWriteArtifact(targetFile, 'bak');
        await targetFile.rename(backupFile.path);
        movedExistingFile = true;
      }
      await tempFile.rename(targetFile.path);
      if (backupFile != null && await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      await _deleteFileIfExistsBestEffort(tempFile, '清理备份写入临时文件');
      if (movedExistingFile &&
          backupFile != null &&
          await backupFile.exists()) {
        await _deleteFileIfExistsBestEffort(targetFile, '回滚前清理失败的目标文件');
        try {
          await backupFile.rename(targetFile.path);
        } on FileSystemException catch (error, stack) {
          silentLog('ai_tool_utils', '回滚安全写入备份', error, stack);
        }
      }
      rethrow;
    }
  }

  /// 删除前执行最终读取校验。
  static Future<AiToolExecutionResult?> deleteFileWithMutationGuard({
    required String toolName,
    required File file,
    required Set<String> previouslyReadFiles,
    AiFileTrackerService? fileTracker,
  }) async {
    return _runWithFileMutationLock(file, () async {
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
    });
  }

  static Future<void> _copyExistingFileMode(
    File sourceFile,
    File targetFile,
  ) async {
    if (Platform.isWindows) return;
    final sourceStat = await FileStat.stat(sourceFile.path);
    if (sourceStat.type == FileSystemEntityType.notFound) return;
    final permissionBits = sourceStat.mode & 0x1FF;
    final chmodResult = await runTrackedProcessOrFailed(
      'chmod',
      <String>[permissionBits.toRadixString(8), targetFile.path],
      timeout: _metadataProcessTimeout,
      tag: 'ai_tool_utils.copy_file_mode',
    );
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
    return ReaderFileType.isTextLikeExtension(extension);
  }

  static bool looksLikeTimeoutMessage(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized.contains('timed out') || normalized.contains('timeout');
  }

  static Future<T?> awaitWithCancellation<T>(
    Future<T> future, {
    Future<void>? cancelSignal,
  }) => awaitWithCancelSignal(future, cancelSignal: cancelSignal);

  // ────────────────────────────────────────────────────────────
  // ripgrep (rg) 命令路径解析
  // 优先使用应用内嵌入的 rg，确保用户无需预装 ripgrep
  // ────────────────────────────────────────────────────────────

  /// 缓存的 rg 可执行文件路径。首次调用时初始化。
  static String? _cachedRgPath;

  /// 获取当前平台的 ripgrep 子目录名称。
  ///
  /// 返回格式：`{arch}-{os}`，例如 `arm64-darwin`、`x64-win32`。
  static Future<String> _getRipgrepPlatformDir() async {
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
      final hostIsAppleSilicon =
          executable.contains('arm64') || await _isAppleSilicon();
      if (hostIsAppleSilicon) {
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
  static Future<bool> _isAppleSilicon() async {
    // 环境变量:运行在 Rosetta 下的 x86_64 二进制,宿主为 Apple Silicon
    final sysctl = Platform.environment['SYSCTL_PROC_TRANSLATED'];
    if (sysctl == '1') return true;

    // 首选:读取内核架构
    try {
      final result = await runTrackedProcessOrFailed(
        'uname',
        <String>['-m'],
        timeout: _metadataProcessTimeout,
        tag: 'ai_tool_utils.detect_apple_silicon',
      );
      if (result.exitCode == 0) {
        final machine = '${result.stdout}'.trim().toLowerCase();
        if (machine == 'arm64' || machine == 'aarch64') return true;
        if (machine == 'x86_64' || machine == 'i386') return false;
      }
    } catch (error, stack) {
      silentLog('ai_tool_utils', '通过 uname 检测 Apple Silicon', error, stack);
    }

    // 回退:Homebrew 在 Apple Silicon 上默认安装到 /opt/homebrew
    return isDirectoryPath('/opt/homebrew/bin', followLinks: true);
  }

  /// 获取应用内嵌入的 ripgrep 路径。
  ///
  /// 查找优先级：
  /// 1. 开发模式：项目根目录的 vendor/ripgrep
  /// 2. macOS 打包：应用包内的 Resources/vendor/ripgrep
  /// 3. Windows 打包：可执行文件同级的 vendor/ripgrep
  static Future<String?> _getEmbeddedRipgrepPath() async {
    final platformDir = await _getRipgrepPlatformDir();
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
      final projectRoot = await _findProjectRoot(executableDir);
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
      final projectRoot = await _findProjectRoot(executableDir);
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

      final projectRoot = await _findProjectRoot(executableDir);
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
            if ((stat.mode & 0x49) == 0) {
              // 尝试添加执行权限
              final chmodResult = await runTrackedProcessOrFailed(
                'chmod',
                <String>['+x', candidate],
                timeout: _metadataProcessTimeout,
                tag: 'ai_tool_utils.rg_chmod',
              );
              if (chmodResult.exitCode != 0) {
                silentLog(
                  'ai_tool_utils',
                  '设置内置 rg 的执行权限',
                  'exit ${chmodResult.exitCode}: ${chmodResult.stderr}',
                );
                continue;
              }
            }
          } catch (error, stack) {
            silentLog('ai_tool_utils', '检查内置 rg 的执行权限', error, stack);
            continue;
          }
        }
        return candidate;
      }
    }

    return null;
  }

  /// 查找项目根目录（通过向上查找 pubspec.yaml）。
  static Future<String?> _findProjectRoot(String startDir) async {
    for (final directory in ancestorDirectoriesFrom(startDir, maxDepth: 10)) {
      if (await isRegularFilePath(
        p.join(directory, 'pubspec.yaml'),
        followLinks: true,
      )) {
        return directory;
      }
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
  /// 2. PATH 环境变量（通过 which/where 命令）
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
      final whichResult = await runTrackedProcessOrFailed(
        whichCmd,
        <String>['rg'],
        timeout: _metadataProcessTimeout,
        tag: 'ai_tool_utils.resolve_rg_path',
      );
      if (whichResult.exitCode == 0) {
        final foundPath =
            splitTrimmedNonEmpty(
              whichResult.stdout.toString(),
              separator: '\n',
            ).firstOrNull ??
            '';
        if (foundPath.isNotEmpty && await File(foundPath).exists()) {
          _cachedRgPath = foundPath;
          return _cachedRgPath;
        }
      }
    } catch (error, stack) {
      silentLog('ai_tool_utils', '通过 PATH 查找 rg', error, stack);
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
        final shellResult = await runTrackedProcessOrFailed(
          '/bin/zsh',
          <String>['-l', '-c', 'which rg'],
          environment: <String, String>{
            'HOME': Platform.environment['HOME'] ?? '',
          },
          timeout: _metadataProcessTimeout,
          tag: 'ai_tool_utils.resolve_rg_login_shell',
        );
        if (shellResult.exitCode == 0) {
          final foundPath = shellResult.stdout.toString().trim();
          if (foundPath.isNotEmpty && await File(foundPath).exists()) {
            _cachedRgPath = foundPath;
            return _cachedRgPath;
          }
        }
      } catch (error, stack) {
        silentLog('ai_tool_utils', '通过登录 Shell 查找 rg', error, stack);
      }
    }

    return null;
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
    Duration timeout = _searchProcessTimeout,
  }) async {
    try {
      final result = await runProcessWithTimeout(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: inheritEnvironment ? null : const <String, String>{},
        includeParentEnvironment: inheritEnvironment,
        timeout: timeout,
        tag: 'ai_tool_utils.run_process_safely',
      );
      return result ??
          ProcessResult(
            -1,
            124,
            '',
            'Process execution timed out or failed to start.',
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
  // 写操作权限确认支持
  // ══════════════════════════════════════════════════════════════════════════

  /// 写操作权限确认默认超时时间（5分钟）。
  /// 调用方可传 [timeoutMs] 覆盖默认值。
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
    final confirmationTimeout = Duration(
      milliseconds: timeoutMs ?? _writeConfirmationTimeoutMs,
    );
    final requestedAt = DateTime.now().toUtc();
    final request = BashCommandApprovalRequest(
      command: commandForApproval,
      workingDirectory: workingDirectory,
      isWriteCommand: true,
      requestedAt: requestedAt,
      expiresAt: requestedAt.add(confirmationTimeout),
    );

    late final _WriteConfirmationOutcome outcome;
    try {
      final approvalFuture = confirmWriteCommand(request)
          .timeout(confirmationTimeout)
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
            onError: (Object _, StackTrace _) =>
                const _WriteConfirmationOutcome.fromDecision(
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

class AiToolProgressReporter {
  AiToolProgressReporter({
    required StringBuffer progress,
    required this.command,
    required this.workingDirectory,
    required this.stopwatch,
    required this.onUpdate,
  }) : _progress = progress;

  final StringBuffer _progress;
  final String command;
  final String workingDirectory;
  final Stopwatch stopwatch;
  final void Function(BashToolExecutionUpdate update)? onUpdate;

  String get output => _progress.toString().trimRight();

  void emit(String stage, String detail) {
    if (_progress.isNotEmpty) _progress.writeln();
    _progress
      ..writeln('stage: $stage')
      ..write('detail: $detail');
    onUpdate?.call(
      BashToolExecutionUpdate(
        phase: BashToolExecutionPhase.running,
        command: command,
        workingDirectory: workingDirectory,
        stdout: output,
        stderr: '',
        durationMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  AiToolExecutionResult errorResult({
    required BashToolExecutionStatus status,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiToolExecutionResult(
      status: status,
      command: command,
      workingDirectory: workingDirectory,
      stdout: output,
      stderr: message,
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: 'status: ${status.storageValue}\nerror: $message',
      metadata: metadata,
    );
  }
}

class AiFileMutationPreparation {
  const AiFileMutationPreparation({
    this.fileTracker,
    this.historyVersionId,
    this.beforeContent,
    this.error,
  });

  final AiFileTrackerService? fileTracker;
  final String? historyVersionId;
  final String? beforeContent;
  final AiToolExecutionResult? error;
}

/// 写确认结果内部类型。
class _WriteConfirmationOutcome {
  const _WriteConfirmationOutcome.fromDecision(this.decision);

  final BashCommandApprovalDecision decision;

  bool get approved => decision == BashCommandApprovalDecision.approved;
  bool get cancelled => decision == BashCommandApprovalDecision.cancelled;
}

class _MissingPathSuggestion {
  const _MissingPathSuggestion({
    required this.path,
    required this.name,
    required this.score,
  });

  final String path;
  final String name;
  final int score;

  bool isBetterThan(_MissingPathSuggestion other) {
    if (score != other.score) return score > other.score;
    final nameComparison = name.compareTo(other.name);
    if (nameComparison != 0) return nameComparison < 0;
    return path.compareTo(other.path) < 0;
  }
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
