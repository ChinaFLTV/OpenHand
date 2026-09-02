import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../../app/support/openhand_paths.dart';
import '../util/bounded_file_io.dart';
import '../util/byte_size_format.dart';

const int maxSettingsDocumentBytes = 8 * kBytesPerMiB;
const int maxLegacyMemoryBytes = 64 * kBytesPerMiB;
const String legacyMigrationMetaTable = 'migration_meta';
const String legacyMigrationStatusNotFound = 'not_found';
const String legacyMigrationStatusImported = 'imported';
const String legacyMigrationStatusTargetPresent = 'target_present';
const String legacyMigrationStatusExplicitClear = 'explicit_clear';

String encodeLegacyMigrationMarker({
  required String status,
  String? sourcePath,
  String? memoryFilePath,
}) {
  return jsonEncode(<String, Object?>{
    'status': status,
    if (sourcePath != null) 'source_path': sourcePath,
    if (memoryFilePath != null) 'memory_file_path': memoryFilePath,
    'completed_at': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<void> markLegacyTargetPresentIfAbsent(
  DatabaseExecutor database, {
  required String key,
}) async {
  await database.insert(legacyMigrationMetaTable, <String, Object?>{
    'key': key,
    'value': encodeLegacyMigrationMarker(
      status: legacyMigrationStatusTargetPresent,
    ),
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

class LegacySettingsDocument {
  const LegacySettingsDocument({
    required this.rootValues,
    required this.modelValues,
  });

  final Map<String, Object?> rootValues;
  final List<Map<String, Object?>> modelValues;

  String? get configuredMemoryFilePath {
    final raw = '${rootValues['user_memory_file'] ?? ''}'.trim();
    if (raw.isEmpty) return null;
    return OpenHandPaths.normalizePath(
      raw,
      defaultPath: defaultLegacyMemoryFilePath(),
    );
  }
}

String defaultLegacySettingsFilePath() {
  return p.join(
    OpenHandPaths.defaultRootDirectoryPath(),
    'settings',
    'SETTINGS.toml',
  );
}

String defaultLegacyMemoryFilePath() {
  return p.join(
    OpenHandPaths.defaultRootDirectoryPath(),
    'memory',
    'user-memory.json',
  );
}

Future<File?> findLegacySettingsFile() async {
  final candidates = <String>[defaultLegacySettingsFilePath()];
  if (Platform.isMacOS) {
    final rawHome = Platform.environment['HOME']?.trim();
    if (rawHome != null && rawHome.isNotEmpty) {
      candidates.add(p.join(rawHome, '.openhand', 'settings', 'SETTINGS.toml'));
    }
  }
  return _firstExistingFile(candidates);
}

Future<LegacySettingsDocument> readLegacySettingsDocument(File file) async {
  final raw = await readBoundedFileString(
    file,
    maxBytes: maxSettingsDocumentBytes,
  );
  return parseLegacySettingsDocument(raw);
}

Future<String?> readLegacyConfiguredMemoryFilePath(File file) async {
  final raw = await readBoundedFileString(
    file,
    maxBytes: maxSettingsDocumentBytes,
  );
  for (final rawLine in const LineSplitter().convert(raw)) {
    final trimmed = rawLine.trimLeft();
    if (trimmed == '[[ai_models]]') break;
    if (!trimmed.startsWith('user_memory_file')) continue;
    final line = _stripInlineComment(rawLine).trim();
    final separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0 ||
        line.substring(0, separatorIndex).trim() != 'user_memory_file') {
      continue;
    }
    final value = _parseLegacySettingValue(
      line.substring(separatorIndex + 1).trim(),
    );
    if (value is! String || value.trim().isEmpty) return null;
    return OpenHandPaths.normalizePath(
      value,
      defaultPath: defaultLegacyMemoryFilePath(),
    );
  }
  return null;
}

LegacySettingsDocument parseLegacySettingsDocument(String rawContent) {
  final rootValues = <String, Object?>{};
  final modelValues = <Map<String, Object?>>[];
  Map<String, Object?>? currentModel;

  for (final rawLine in const LineSplitter().convert(rawContent)) {
    final line = _stripInlineComment(rawLine).trim();
    if (line.isEmpty) continue;
    if (line == '[[ai_models]]') {
      currentModel = <String, Object?>{};
      modelValues.add(currentModel);
      continue;
    }
    if (line.startsWith('[') || line.endsWith(']')) {
      throw const FormatException('不支持的旧版设置区段。');
    }

    final separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0) {
      throw FormatException('旧版设置项格式无效：$line');
    }
    final key = line.substring(0, separatorIndex).trim();
    if (key.isEmpty) {
      throw FormatException('旧版设置项格式无效：$line');
    }
    final value = _parseLegacySettingValue(
      line.substring(separatorIndex + 1).trim(),
    );
    (currentModel ?? rootValues)[key] = value;
  }

  return LegacySettingsDocument(
    rootValues: rootValues,
    modelValues: modelValues,
  );
}

List<File> legacyMemoryFileCandidates({String? configuredPath}) {
  final paths = <String>[
    if (configuredPath != null && configuredPath.trim().isNotEmpty)
      configuredPath,
    defaultLegacyMemoryFilePath(),
    p.join(
      OpenHandPaths.applicationDirectoryPath(),
      '.openhand',
      'memory',
      'user-memory.json',
    ),
  ];
  final databasePath = p.normalize(
    p.absolute(OpenHandPaths.defaultDatabasePath()),
  );
  final seen = <String>{};
  return <File>[
    for (final path in paths)
      if (seen.add(p.normalize(p.absolute(path))) &&
          !p.equals(p.normalize(p.absolute(path)), databasePath))
        File(path),
  ];
}

Future<File?> findLegacyMemoryFile({String? configuredPath}) {
  return _firstExistingFile(
    legacyMemoryFileCandidates(
      configuredPath: configuredPath,
    ).map((file) => file.path),
  );
}

Future<File?> _firstExistingFile(Iterable<String> paths) async {
  final seen = <String>{};
  for (final path in paths) {
    final normalized = p.normalize(p.absolute(path));
    if (!seen.add(normalized)) continue;
    final file = File(path);
    if (await regularFileExistsBounded(file)) return file;
  }
  return null;
}

Object? _parseLegacySettingValue(String rawValue) {
  if (rawValue.startsWith('"') && rawValue.endsWith('"')) {
    return jsonDecode(rawValue);
  }
  final intValue = int.tryParse(rawValue);
  if (intValue != null) return intValue;
  if (rawValue == 'true') return true;
  if (rawValue == 'false') return false;
  throw FormatException('不支持的旧版设置值：$rawValue');
}

String _stripInlineComment(String rawLine) {
  final buffer = StringBuffer();
  var inString = false;
  var escaping = false;
  for (final rune in rawLine.runes) {
    final char = String.fromCharCode(rune);
    if (escaping) {
      buffer.write(char);
      escaping = false;
      continue;
    }
    if (char == r'\') {
      buffer.write(char);
      escaping = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      buffer.write(char);
      continue;
    }
    if (char == '#' && !inString) break;
    buffer.write(char);
  }
  if (inString || escaping) {
    throw const FormatException('旧版设置字符串未正确结束。');
  }
  return buffer.toString();
}
