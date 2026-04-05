import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../app/support/openhand_paths.dart';
import '../../shared/data/atomic_file_operations.dart';
import 'model/hardness_session_record.dart';

/// Persists a single Hardness Engineering session record to disk so the
/// session entry survives application restarts.
///
/// The record is stored as a JSON file at
/// `~/.openhand/sessions/hardness-session.json`.
class HardnessSessionStore {
  HardnessSessionStore({String? filePath})
    : _filePath =
          filePath ??
          p.join(
            OpenHandPaths.defaultSessionsDirectoryPath(),
            'hardness-session.json',
          );

  final String _filePath;

  /// Loads the persisted record, or returns `null` if none exists.
  Future<HardnessSessionRecord?> load() async {
    final file = File(_filePath);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return HardnessSessionRecord.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// Persists [record] to disk (atomic write).
  Future<void> save(HardnessSessionRecord record) async {
    final dir = Directory(p.dirname(_filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final content = const JsonEncoder.withIndent('  ').convert(record.toJson());
    await writeFileAtomically(File(_filePath), content);
  }

  /// Removes the persisted record.
  Future<void> clear() async {
    final file = File(_filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
