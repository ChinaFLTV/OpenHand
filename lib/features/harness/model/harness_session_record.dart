import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../service/harness_orchestrator.dart';
import 'harness_phase.dart';
import 'harness_session_config.dart';

const Object _harnessSessionRecordUnset = Object();
const int _maxHarnessPersistedPhaseLogs = 16;
const int _maxHarnessSessionIdCharacters = 256;
const int _maxHarnessSessionTitleCharacters = 512;
const int _maxHarnessSessionErrorCharacters = 4000;
const int _maxHarnessStorageValueCharacters = 64;

/// 可跨应用重启恢复的 Harness 工程会话元数据。
class HarnessSessionRecord {
  const HarnessSessionRecord({
    required this.id,
    required this.title,
    required this.config,
    required this.statusValue,
    required this.createdAt,
    required this.updatedAt,
    this.phaseLogs = const <HarnessPhaseLogSnapshot>[],
    this.errorMessage,
    this.currentPhaseValue,
    this.manualPhaseInputRequested = false,
    this.queuedManualPhaseInput,
    this.queuedManualPhaseInputPhaseValue,
  });

  final String id;

  /// 从任务首行生成的短标题。
  final String title;

  final HarnessSessionConfig config;

  /// 使用 [HarnessOrchestratorStatus.name] 序列化的状态。
  final String statusValue;

  final DateTime createdAt;
  final DateTime updatedAt;
  final List<HarnessPhaseLogSnapshot> phaseLogs;
  final String? errorMessage;
  final String? currentPhaseValue;
  final bool manualPhaseInputRequested;
  final String? queuedManualPhaseInput;
  final String? queuedManualPhaseInputPhaseValue;

  HarnessOrchestratorStatus get status {
    return enumByNameOr(
      HarnessOrchestratorStatus.values,
      statusValue,
      fallback: HarnessOrchestratorStatus.idle,
    );
  }

  HarnessPhase? get currentPhase {
    final value = currentPhaseValue;
    if (value == null || value.isEmpty) {
      return null;
    }
    return HarnessPhase.fromStorageValue(value);
  }

  HarnessPhase? get queuedManualPhaseInputPhase {
    final value = queuedManualPhaseInputPhaseValue;
    if (value == null || value.isEmpty) {
      return null;
    }
    return HarnessPhase.fromStorageValue(value);
  }

  HarnessSessionRecord copyWith({
    String? id,
    String? title,
    HarnessSessionConfig? config,
    String? statusValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<HarnessPhaseLogSnapshot>? phaseLogs,
    Object? errorMessage = _harnessSessionRecordUnset,
    Object? currentPhaseValue = _harnessSessionRecordUnset,
    bool? manualPhaseInputRequested,
    Object? queuedManualPhaseInput = _harnessSessionRecordUnset,
    Object? queuedManualPhaseInputPhaseValue = _harnessSessionRecordUnset,
  }) {
    return HarnessSessionRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      config: config ?? this.config,
      statusValue: statusValue ?? this.statusValue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      phaseLogs: phaseLogs ?? this.phaseLogs,
      errorMessage: identical(errorMessage, _harnessSessionRecordUnset)
          ? this.errorMessage
          : errorMessage as String?,
      currentPhaseValue:
          identical(currentPhaseValue, _harnessSessionRecordUnset)
          ? this.currentPhaseValue
          : currentPhaseValue as String?,
      manualPhaseInputRequested:
          manualPhaseInputRequested ?? this.manualPhaseInputRequested,
      queuedManualPhaseInput:
          identical(queuedManualPhaseInput, _harnessSessionRecordUnset)
          ? this.queuedManualPhaseInput
          : queuedManualPhaseInput as String?,
      queuedManualPhaseInputPhaseValue:
          identical(
            queuedManualPhaseInputPhaseValue,
            _harnessSessionRecordUnset,
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

  static HarnessSessionRecord fromJson(Map<String, Object?> json) {
    final configMap = stringKeyedMapFromValue(json['config']);
    final phaseLogs = <HarnessPhaseLogSnapshot>[];
    final rawPhaseLogs = json['phase_logs'];
    if (rawPhaseLogs is List) {
      final count = rawPhaseLogs.length < _maxHarnessPersistedPhaseLogs
          ? rawPhaseLogs.length
          : _maxHarnessPersistedPhaseLogs;
      for (var index = 0; index < count; index++) {
        final snapshot = HarnessPhaseLogSnapshot.fromJson(
          stringKeyedMapFromValue(rawPhaseLogs[index]),
        );
        if (snapshot != null) {
          phaseLogs.add(snapshot);
        }
      }
    }
    final now = DateTime.now().toUtc();
    final legacyManualReviewInputRequested = boolFromValue(
      json['manual_review_input_requested'],
    );
    final legacyQueuedManualReviewInput = json['queued_manual_review_input'];
    final queuedManualPhaseInput = json['queued_manual_phase_input'] == null
        ? (legacyQueuedManualReviewInput == null
              ? null
              : clipTextByCodeUnits(
                  '$legacyQueuedManualReviewInput',
                  kHarnessManualPhaseInputMaxCharacters,
                  suffix: '',
                ))
        : clipTextByCodeUnits(
            '${json['queued_manual_phase_input']}',
            kHarnessManualPhaseInputMaxCharacters,
            suffix: '',
          );
    final queuedManualPhaseInputPhaseValue =
        json['queued_manual_phase_input_phase'] == null
        ? (queuedManualPhaseInput == null
              ? null
              : HarnessPhase.reviewing.storageValue)
        : '${json['queued_manual_phase_input_phase']}';
    return HarnessSessionRecord(
      id: clipTextByCodeUnits(
        '${json['id'] ?? ''}',
        _maxHarnessSessionIdCharacters,
        suffix: '',
      ),
      title: clipTextByCodeUnits(
        '${json['title'] ?? ''}',
        _maxHarnessSessionTitleCharacters,
        suffix: '',
      ),
      config: HarnessSessionConfig.fromJson(configMap),
      statusValue: clipTextByCodeUnits(
        '${json['status'] ?? 'idle'}',
        _maxHarnessStorageValueCharacters,
        suffix: '',
      ),
      createdAt: dateTimeFromValue(json['created_at'])?.toUtc() ?? now,
      updatedAt: dateTimeFromValue(json['updated_at'])?.toUtc() ?? now,
      phaseLogs: phaseLogs,
      errorMessage: json['error_message'] == null
          ? null
          : clipTextByCodeUnitsWithEllipsis(
              '${json['error_message']}',
              _maxHarnessSessionErrorCharacters,
            ),
      currentPhaseValue: json['current_phase'] == null
          ? null
          : clipTextByCodeUnits(
              '${json['current_phase']}',
              _maxHarnessStorageValueCharacters,
              suffix: '',
            ),
      manualPhaseInputRequested:
          boolFromValue(json['manual_phase_input_requested']) ||
          (json['manual_phase_input_requested'] == null &&
              legacyManualReviewInputRequested),
      queuedManualPhaseInput: queuedManualPhaseInput,
      queuedManualPhaseInputPhaseValue: queuedManualPhaseInputPhaseValue == null
          ? null
          : clipTextByCodeUnits(
              queuedManualPhaseInputPhaseValue,
              _maxHarnessStorageValueCharacters,
              suffix: '',
            ),
    );
  }
}
