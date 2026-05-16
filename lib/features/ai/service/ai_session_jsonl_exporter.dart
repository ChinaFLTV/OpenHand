import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/silent_log.dart';
import '../model/ai_session.dart';
import '../model/ai_session_message.dart';
import '../../hardness/index.dart';

/// A simple cooperative cancellation token for export operations.
class ExportCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() {
    _cancelled = true;
  }
}

/// Progress payload reported during an export operation.
class ExportProgress {
  const ExportProgress({required this.processed, required this.total});
  final int processed;
  final int total;
  double get fraction {
    if (total <= 0) return 0;
    final value = processed / total;
    if (value.isNaN || value.isInfinite) return 0;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}

/// Result enum for an export attempt.
enum ExportResultKind { success, cancelled, failure }

class ExportResult {
  const ExportResult({
    required this.kind,
    this.bytesWritten = 0,
    this.linesWritten = 0,
    this.error,
  });
  final ExportResultKind kind;
  final int bytesWritten;
  final int linesWritten;
  final Object? error;
}

/// Yield to the event loop so the UI thread stays responsive while exporting
/// a large session. Using `Future.delayed(Duration.zero)` rather than just
/// `Future(() {})` ensures we drain microtasks AND a render frame.
Future<void> _yieldToEventLoop() => Future<void>.delayed(Duration.zero);

/// Number of lines to write before flushing + yielding to the event loop.
const int _flushEvery = 32;

/// User-tunable configuration for an AI session export operation.
class AiSessionExportConfig {
  const AiSessionExportConfig({
    this.roles,
    this.kinds,
    this.includeDeleted = false,
    this.startIndex,
    this.endIndex,
    this.prettyPrint = false,
  });

  /// When non-null, only messages whose [AiSessionMessageRole] is in this
  /// set will be exported. `null` means "all roles".
  final Set<AiSessionMessageRole>? roles;

  /// When non-null, only messages whose [AiSessionMessageKind] is in this
  /// set will be exported. `null` means "all kinds".
  final Set<AiSessionMessageKind>? kinds;

  /// When `true`, include messages where `isDeleted == true`.
  final bool includeDeleted;

  /// 1-based inclusive lower bound applied to the message ordering before
  /// any role/kind filter is run. `null` means "no lower bound".
  final int? startIndex;

  /// 1-based inclusive upper bound applied to the message ordering before
  /// any role/kind filter is run. `null` means "no upper bound".
  final int? endIndex;

  /// When `true`, JSON is pretty-printed (2-space indent). Note: this
  /// breaks JSONL strictness because each entry will span multiple lines,
  /// but is convenient for human inspection.
  final bool prettyPrint;

  /// All-defaults configuration (every role, every kind, no range filter,
  /// skip deleted messages, single-line JSON).
  static const AiSessionExportConfig defaults = AiSessionExportConfig();

  Map<String, Object?> toJson() => <String, Object?>{
        'roles': roles?.map((role) => role.storageValue).toList(),
        'kinds': kinds?.map((kind) => kind.storageValue).toList(),
        'include_deleted': includeDeleted,
        'start_index': startIndex,
        'end_index': endIndex,
        'pretty_print': prettyPrint,
      };
}

/// User-tunable configuration for a Hardness session export operation.
class HardnessSessionExportConfig {
  const HardnessSessionExportConfig({
    this.startIndex,
    this.endIndex,
    this.prettyPrint = false,
  });

  /// 1-based inclusive lower bound on phase logs.
  final int? startIndex;

  /// 1-based inclusive upper bound on phase logs.
  final int? endIndex;

  final bool prettyPrint;

  static const HardnessSessionExportConfig defaults =
      HardnessSessionExportConfig();

  Map<String, Object?> toJson() => <String, Object?>{
        'start_index': startIndex,
        'end_index': endIndex,
        'pretty_print': prettyPrint,
      };
}

String _encodePayload(Map<String, Object?> payload, {required bool pretty}) {
  if (!pretty) return jsonEncode(payload);
  return const JsonEncoder.withIndent('  ').convert(payload);
}

/// Exports an [AiSession] to a JSONL file at [destinationPath].
///
/// The format mirrors the Hugging Face dataset card layout used by `pi-mono`:
/// the first line is a `{"type":"session", ...}` header, followed by one
/// `{"type":"message", ...}` line per [AiSessionMessage].
///
/// All non-deleted messages are exported regardless of [AiSessionMessageKind]
/// (user / assistant / reasoning / tool_call / tool / mcp / skill / hook /
/// self_learning / status / compression_point).
///
/// Reports incremental progress through [onProgress] and honours
/// [cancelToken]. On cancellation or error, the partial file is removed.
Future<ExportResult> exportAiSessionToJsonl({
  required AiSession session,
  required String destinationPath,
  required ExportCancelToken cancelToken,
  AiSessionExportConfig config = AiSessionExportConfig.defaults,
  void Function(ExportProgress progress)? onProgress,
}) async {
  final file = File(destinationPath);
  IOSink? sink;
  var lines = 0;
  var bytes = 0;
  try {
    final localSink = file.openWrite();
    sink = localSink;

    // Apply range first (1-based inclusive bounds), then role / kind /
    // deleted filters. Range is interpreted against the full ordered
    // message list so users can reason about indices the same way the UI
    // shows them.
    final fullMessages = session.messages;
    final lower = (config.startIndex != null && config.startIndex! >= 1)
        ? config.startIndex! - 1
        : 0;
    final upperRaw = (config.endIndex != null && config.endIndex! >= 1)
        ? config.endIndex!
        : fullMessages.length;
    final upper = upperRaw > fullMessages.length ? fullMessages.length : upperRaw;
    final ranged = (lower >= upper)
        ? const <AiSessionMessage>[]
        : fullMessages.sublist(lower, upper);

    final messages = ranged.where((message) {
      if (!config.includeDeleted && message.isDeleted) return false;
      final roleFilter = config.roles;
      if (roleFilter != null && !roleFilter.contains(message.role)) {
        return false;
      }
      final kindFilter = config.kinds;
      if (kindFilter != null && !kindFilter.contains(message.kind)) {
        return false;
      }
      return true;
    }).toList(growable: false);
    final total = messages.length + 1; // +1 for the session header line.

    Future<void> emit(Map<String, Object?> payload) async {
      final encoded = _encodePayload(payload, pretty: config.prettyPrint);
      localSink.write(encoded);
      localSink.write('\n');
      bytes += encoded.length + 1;
      lines += 1;
    }

    final headerPayload = <String, Object?>{
      'type': 'session',
      'version': 1,
      'id': session.id,
      'title': session.title,
      'template_id': session.templateId,
      'template_name': session.templateName,
      'template_icon_name': session.templateIconName,
      'template_internal_version': session.templateInternalVersion,
      'created_at': session.createdAt.toUtc().toIso8601String(),
      'updated_at': session.updatedAt.toUtc().toIso8601String(),
      'message_count': messages.length,
      'total_message_count': fullMessages.length,
      'last_used_model_id': session.lastUsedModelId,
      'last_used_model_label': session.lastUsedModelLabel,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'export_config': config.toJson(),
    };
    await emit(headerPayload);
    onProgress?.call(ExportProgress(processed: lines, total: total));

    for (var i = 0; i < messages.length; i++) {
      if (cancelToken.isCancelled) {
        await localSink.flush();
        await localSink.close();
        sink = null;
        if (await file.exists()) {
          await file.delete();
        }
        return ExportResult(
          kind: ExportResultKind.cancelled,
          bytesWritten: bytes,
          linesWritten: lines,
        );
      }
      final message = messages[i];
      await emit(<String, Object?>{
        'type': 'message',
        ...message.toJson(),
      });
      if ((i + 1) % _flushEvery == 0) {
        await localSink.flush();
        onProgress?.call(ExportProgress(processed: lines, total: total));
        await _yieldToEventLoop();
      }
    }

    await localSink.flush();
    await localSink.close();
    sink = null;
    onProgress?.call(ExportProgress(processed: lines, total: total));
    return ExportResult(
      kind: ExportResultKind.success,
      bytesWritten: bytes,
      linesWritten: lines,
    );
  } catch (error, stack) {
    silentLog('ai_session_jsonl_exporter', 'export', error, stack);
    try {
      await sink?.close();
    } catch (closeError, closeStack) {
      silentLog(
        'ai_session_jsonl_exporter',
        'sink close after failure',
        closeError,
        closeStack,
      );
    }
    sink = null;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (deleteError, deleteStack) {
      silentLog(
        'ai_session_jsonl_exporter',
        'cleanup partial file',
        deleteError,
        deleteStack,
      );
    }
    return ExportResult(
      kind: ExportResultKind.failure,
      bytesWritten: bytes,
      linesWritten: lines,
      error: error,
    );
  } finally {
    // `sink` was set to null whenever it's been closed. Defensive close in
    // case an unexpected return path reaches `finally` with a live sink.
    if (sink != null) {
      try {
        await sink.close();
      } catch (closeError, closeStack) {
        silentLog(
          'ai_session_jsonl_exporter',
          'sink close in finally',
          closeError,
          closeStack,
        );
      }
    }
  }
}

/// Exports a [HardnessSessionRecord] to a JSONL file at [destinationPath].
///
/// Layout:
///   line 1   : `{"type":"hardness_session", ...}` header (sans phase_logs).
///   line 2..N: one `{"type":"phase_log", ...}` per [HardnessPhaseLogSnapshot].
Future<ExportResult> exportHardnessSessionToJsonl({
  required HardnessSessionRecord record,
  required String destinationPath,
  required ExportCancelToken cancelToken,
  HardnessSessionExportConfig config = HardnessSessionExportConfig.defaults,
  void Function(ExportProgress progress)? onProgress,
}) async {
  final file = File(destinationPath);
  IOSink? sink;
  var lines = 0;
  var bytes = 0;
  try {
    final localSink = file.openWrite();
    sink = localSink;
    final fullLogs = record.phaseLogs;
    final lower = (config.startIndex != null && config.startIndex! >= 1)
        ? config.startIndex! - 1
        : 0;
    final upperRaw = (config.endIndex != null && config.endIndex! >= 1)
        ? config.endIndex!
        : fullLogs.length;
    final upper = upperRaw > fullLogs.length ? fullLogs.length : upperRaw;
    final logs = (lower >= upper) ? const [] : fullLogs.sublist(lower, upper);
    final total = logs.length + 1;

    Future<void> emit(Map<String, Object?> payload) async {
      final encoded = _encodePayload(payload, pretty: config.prettyPrint);
      localSink.write(encoded);
      localSink.write('\n');
      bytes += encoded.length + 1;
      lines += 1;
    }

    final fullJson = record.toJson();
    fullJson.remove('phase_logs');
    await emit(<String, Object?>{
      'type': 'hardness_session',
      'version': 1,
      'phase_log_count': logs.length,
      'total_phase_log_count': fullLogs.length,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'export_config': config.toJson(),
      ...fullJson,
    });
    onProgress?.call(ExportProgress(processed: lines, total: total));

    for (var i = 0; i < logs.length; i++) {
      if (cancelToken.isCancelled) {
        await localSink.flush();
        await localSink.close();
        sink = null;
        if (await file.exists()) {
          await file.delete();
        }
        return ExportResult(
          kind: ExportResultKind.cancelled,
          bytesWritten: bytes,
          linesWritten: lines,
        );
      }
      await emit(<String, Object?>{
        'type': 'phase_log',
        'sort_order': i,
        ...logs[i].toJson(),
      });
      if ((i + 1) % _flushEvery == 0) {
        await localSink.flush();
        onProgress?.call(ExportProgress(processed: lines, total: total));
        await _yieldToEventLoop();
      }
    }

    await localSink.flush();
    await localSink.close();
    sink = null;
    onProgress?.call(ExportProgress(processed: lines, total: total));
    return ExportResult(
      kind: ExportResultKind.success,
      bytesWritten: bytes,
      linesWritten: lines,
    );
  } catch (error, stack) {
    silentLog('ai_session_jsonl_exporter', 'export hardness', error, stack);
    try {
      await sink?.close();
    } catch (closeError, closeStack) {
      silentLog(
        'ai_session_jsonl_exporter',
        'sink close after hardness failure',
        closeError,
        closeStack,
      );
    }
    sink = null;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (deleteError, deleteStack) {
      silentLog(
        'ai_session_jsonl_exporter',
        'cleanup partial hardness file',
        deleteError,
        deleteStack,
      );
    }
    return ExportResult(
      kind: ExportResultKind.failure,
      bytesWritten: bytes,
      linesWritten: lines,
      error: error,
    );
  } finally {
    if (sink != null) {
      try {
        await sink.close();
      } catch (closeError, closeStack) {
        silentLog(
          'ai_session_jsonl_exporter',
          'sink close in hardness finally',
          closeError,
          closeStack,
        );
      }
    }
  }
}
