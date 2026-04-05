import '../hardness_orchestrator.dart';
import 'hardness_phase.dart';
import 'hardness_session_config.dart';

const Object _hardnessSessionRecordUnset = Object();

/// Persisted metadata for a single Hardness Engineering session.
/// Saved to disk so the session survives app restarts.
class HardnessSessionRecord {
  const HardnessSessionRecord({
    required this.id,
    required this.title,
    required this.config,
    required this.statusValue,
    required this.createdAt,
    required this.updatedAt,
    this.phaseLogs = const <HardnessPhaseLogSnapshot>[],
    this.errorMessage,
    this.currentPhaseValue,
  });

  final String id;

  /// Short title derived from the first line of [config.task].
  final String title;

  final HardnessSessionConfig config;

  /// Serialised status string (uses [HardnessOrchestratorStatus.name]).
  final String statusValue;

  final DateTime createdAt;
  final DateTime updatedAt;
  final List<HardnessPhaseLogSnapshot> phaseLogs;
  final String? errorMessage;
  final String? currentPhaseValue;

  /// Parsed status from [statusValue].
  HardnessOrchestratorStatus get status {
    return HardnessOrchestratorStatus.values.firstWhere(
      (s) => s.name == statusValue,
      orElse: () => HardnessOrchestratorStatus.idle,
    );
  }

  HardnessPhase? get currentPhase {
    final value = currentPhaseValue;
    if (value == null || value.isEmpty) {
      return null;
    }
    return HardnessPhase.fromStorageValue(value);
  }

  HardnessSessionRecord copyWith({
    String? id,
    String? title,
    HardnessSessionConfig? config,
    String? statusValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<HardnessPhaseLogSnapshot>? phaseLogs,
    Object? errorMessage = _hardnessSessionRecordUnset,
    Object? currentPhaseValue = _hardnessSessionRecordUnset,
  }) {
    return HardnessSessionRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      config: config ?? this.config,
      statusValue: statusValue ?? this.statusValue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      phaseLogs: phaseLogs ?? this.phaseLogs,
      errorMessage: identical(errorMessage, _hardnessSessionRecordUnset)
          ? this.errorMessage
          : errorMessage as String?,
      currentPhaseValue:
          identical(currentPhaseValue, _hardnessSessionRecordUnset)
          ? this.currentPhaseValue
          : currentPhaseValue as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'config': config.toJson(),
    'status': statusValue,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'phase_logs': phaseLogs.map((entry) => entry.toJson()).toList(),
    'error_message': errorMessage,
    'current_phase': currentPhaseValue,
  };

  static HardnessSessionRecord fromJson(Map<String, Object?> json) {
    final configRaw = json['config'];
    final configMap = configRaw is Map<String, Object?>
        ? configRaw
        : configRaw is Map
        ? Map<String, Object?>.from(configRaw)
        : const <String, Object?>{};
    final phaseLogsRaw = json['phase_logs'];
    final phaseLogs = <HardnessPhaseLogSnapshot>[];
    if (phaseLogsRaw is List) {
      for (final entry in phaseLogsRaw) {
        if (entry is! Map) {
          continue;
        }
        final snapshot = HardnessPhaseLogSnapshot.fromJson(
          Map<String, Object?>.from(entry),
        );
        if (snapshot != null) {
          phaseLogs.add(snapshot);
        }
      }
    }
    final now = DateTime.now().toUtc();
    return HardnessSessionRecord(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      config: HardnessSessionConfig.fromJson(configMap),
      statusValue: '${json['status'] ?? 'idle'}',
      createdAt: DateTime.tryParse('${json['created_at']}')?.toUtc() ?? now,
      updatedAt: DateTime.tryParse('${json['updated_at']}')?.toUtc() ?? now,
      phaseLogs: phaseLogs,
      errorMessage: json['error_message'] == null
          ? null
          : '${json['error_message']}',
      currentPhaseValue: json['current_phase'] == null
          ? null
          : '${json['current_phase']}',
    );
  }
}
