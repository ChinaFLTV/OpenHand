import '../service/hardness_orchestrator.dart';
import 'hardness_phase.dart';
import 'hardness_session_config.dart';

const Object _hardnessSessionRecordUnset = Object();

/// Persisted metadata for a single Harness Engineering session.
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
    this.manualPhaseInputRequested = false,
    this.queuedManualPhaseInput,
    this.queuedManualPhaseInputPhaseValue,
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
  final bool manualPhaseInputRequested;
  final String? queuedManualPhaseInput;
  final String? queuedManualPhaseInputPhaseValue;

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

  HardnessPhase? get queuedManualPhaseInputPhase {
    final value = queuedManualPhaseInputPhaseValue;
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
    bool? manualPhaseInputRequested,
    Object? queuedManualPhaseInput = _hardnessSessionRecordUnset,
    Object? queuedManualPhaseInputPhaseValue = _hardnessSessionRecordUnset,
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
      manualPhaseInputRequested:
          manualPhaseInputRequested ?? this.manualPhaseInputRequested,
      queuedManualPhaseInput:
          identical(queuedManualPhaseInput, _hardnessSessionRecordUnset)
          ? this.queuedManualPhaseInput
          : queuedManualPhaseInput as String?,
      queuedManualPhaseInputPhaseValue:
          identical(
            queuedManualPhaseInputPhaseValue,
            _hardnessSessionRecordUnset,
          )
          ? this.queuedManualPhaseInputPhaseValue
          : queuedManualPhaseInputPhaseValue as String?,
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
    'manual_phase_input_requested': manualPhaseInputRequested,
    'queued_manual_phase_input': queuedManualPhaseInput,
    'queued_manual_phase_input_phase': queuedManualPhaseInputPhaseValue,
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
    final legacyManualReviewInputRequested =
        json['manual_review_input_requested'] == true;
    final legacyQueuedManualReviewInput = json['queued_manual_review_input'];
    final queuedManualPhaseInput = json['queued_manual_phase_input'] == null
        ? (legacyQueuedManualReviewInput == null
              ? null
              : '$legacyQueuedManualReviewInput')
        : '${json['queued_manual_phase_input']}';
    final queuedManualPhaseInputPhaseValue =
        json['queued_manual_phase_input_phase'] == null
        ? (queuedManualPhaseInput == null
              ? null
              : HardnessPhase.reviewing.storageValue)
        : '${json['queued_manual_phase_input_phase']}';
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
      manualPhaseInputRequested:
          json['manual_phase_input_requested'] == true ||
          (json['manual_phase_input_requested'] == null &&
              legacyManualReviewInputRequested),
      queuedManualPhaseInput: queuedManualPhaseInput,
      queuedManualPhaseInputPhaseValue: queuedManualPhaseInputPhaseValue,
    );
  }
}
