import 'dart:async';
import 'dart:io';

import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/bounded_json_conversion.dart';
import '../../data/openrouter_model_profile_store.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_transport_client.dart';
import 'openrouter_model_profile_mapper.dart';

final Uri openRouterModelsUri = Uri.parse(
  'https://openrouter.ai/api/v1/models',
);

enum OpenRouterSyncPhase { fetching, decoding, processing, completed, failed }

class OpenRouterSyncProgress {
  const OpenRouterSyncProgress({
    required this.phase,
    required this.total,
    required this.processed,
    required this.upserted,
    required this.skipped,
    required this.failed,
    required this.speed,
    required this.elapsed,
    required this.detail,
    this.error,
  });

  final OpenRouterSyncPhase phase;
  final int total;
  final int processed;
  final int upserted;
  final int skipped;
  final int failed;
  final double speed;
  final Duration elapsed;
  final String detail;
  final Object? error;

  double get fraction =>
      total <= 0 ? 0 : (processed / total).clamp(0, 1).toDouble();
}

class OpenRouterSyncResult {
  const OpenRouterSyncResult({
    required this.total,
    required this.processed,
    required this.upserted,
    required this.skipped,
    required this.failed,
    required this.elapsed,
  });

  final int total;
  final int processed;
  final int upserted;
  final int skipped;
  final int failed;
  final Duration elapsed;
}

/// 从 OpenRouter 获取模型目录并批量写入本地档案缓存。
class OpenRouterModelSyncService {
  OpenRouterModelSyncService({AiTransportClient? transport})
    : _transport = transport ?? AiTransportClient(),
      _ownsTransport = transport == null;

  static const int _batchSize = 400;
  static const int _maxResponseBytes = 128 * 1024 * 1024;
  static const int _maxJsonDepth = 64;
  static const int _maxJsonContainerItems = 524288;
  static const int _maxJsonNodes = 4194304;
  static const Duration _requestTimeout = Duration(minutes: 2);

  final AiTransportClient _transport;
  final bool _ownsTransport;
  Future<OpenRouterSyncResult>? _active;

  Future<OpenRouterSyncResult> sync({
    void Function(OpenRouterSyncProgress progress)? onProgress,
  }) {
    final active = _active;
    if (active != null) return active;
    late final Future<OpenRouterSyncResult> operation;
    operation = _run(onProgress).whenComplete(() {
      if (identical(_active, operation)) _active = null;
    });
    _active = operation;
    return operation;
  }

  Future<OpenRouterSyncResult> _run(
    void Function(OpenRouterSyncProgress progress)? onProgress,
  ) async {
    final stopwatch = Stopwatch()..start();
    void report({
      required OpenRouterSyncPhase phase,
      int total = 0,
      int processed = 0,
      int upserted = 0,
      int skipped = 0,
      int failed = 0,
      double speed = 0,
      String detail = '',
      Object? error,
    }) {
      try {
        onProgress?.call(
          OpenRouterSyncProgress(
            phase: phase,
            total: total,
            processed: processed,
            upserted: upserted,
            skipped: skipped,
            failed: failed,
            speed: speed,
            elapsed: stopwatch.elapsed,
            detail: detail,
            error: error,
          ),
        );
      } catch (_) {
        // 进度展示不应影响后台同步任务。
      }
    }

    report(phase: OpenRouterSyncPhase.fetching, detail: '正在请求 OpenRouter 模型目录');
    try {
      final response = await _transport.get(
        uri: openRouterModelsUri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'User-Agent': 'OpenHand model profile sync',
        },
        timeout: _requestTimeout,
        maxResponseBytes: _maxResponseBytes,
      );
      if (!isHttpSuccessStatus(response.statusCode)) {
        throw HttpException(
          'OpenRouter 返回 HTTP ${response.statusCode}：${_preview(response.body)}',
        );
      }
      report(phase: OpenRouterSyncPhase.decoding, detail: '正在解析模型目录数据');
      final decoded = decodeJsonTextWithinBounds(
        response.body,
        maxTextCodeUnits: _maxResponseBytes,
        maxDepth: _maxJsonDepth,
        maxContainerItems: _maxJsonContainerItems,
        maxTotalNodes: _maxJsonNodes,
        maxStringCodeUnits: _maxResponseBytes,
        maxTotalStringCodeUnits: _maxResponseBytes,
      );
      if (decoded is! Map) {
        throw const FormatException('OpenRouter 响应不是 JSON 对象。');
      }
      final rawModels = decoded['data'];
      if (rawModels is! List) {
        throw const FormatException('OpenRouter 响应缺少 data 模型数组。');
      }
      final total = rawModels.length;
      var processed = 0;
      var upserted = 0;
      var skipped = 0;
      var failed = 0;
      report(
        phase: OpenRouterSyncPhase.processing,
        total: total,
        detail: '已获取 $total 条模型，开始转换',
      );
      for (var offset = 0; offset < rawModels.length; offset += _batchSize) {
        final end = (offset + _batchSize).clamp(0, rawModels.length).toInt();
        final entries = <MapEntry<String, AiModelProfile>>[];
        final idsInBatch = <String>{};
        for (final raw in rawModels.sublist(offset, end)) {
          processed += 1;
          try {
            final profile = mapOpenRouterModel(raw);
            if (profile == null) {
              skipped += 1;
              continue;
            }
            final id = raw is Map ? '${raw['id'] ?? ''}'.trim() : '';
            final normalizedId = id.toLowerCase();
            if (normalizedId.isEmpty || !idsInBatch.add(normalizedId)) {
              skipped += 1;
              continue;
            }
            entries.add(MapEntry(id, profile));
          } catch (_) {
            failed += 1;
          }
        }
        if (entries.isNotEmpty) {
          await OpenRouterModelProfileStore.instance.upsertBatch(entries);
          upserted += entries.length;
        }
        final seconds = stopwatch.elapsedMilliseconds / 1000;
        report(
          phase: OpenRouterSyncPhase.processing,
          total: total,
          processed: processed,
          upserted: upserted,
          skipped: skipped,
          failed: failed,
          speed: seconds <= 0 ? 0 : processed / seconds,
          detail: '正在处理第 $processed / $total 条模型',
        );
      }
      final result = OpenRouterSyncResult(
        total: total,
        processed: processed,
        upserted: upserted,
        skipped: skipped,
        failed: failed,
        elapsed: stopwatch.elapsed,
      );
      report(
        phase: OpenRouterSyncPhase.completed,
        total: total,
        processed: processed,
        upserted: upserted,
        skipped: skipped,
        failed: failed,
        speed:
            processed /
            (stopwatch.elapsedMilliseconds / 1000).clamp(
              0.001,
              double.infinity,
            ),
        detail: '同步完成',
      );
      return result;
    } catch (error) {
      report(phase: OpenRouterSyncPhase.failed, detail: '同步失败', error: error);
      rethrow;
    }
  }

  static String _preview(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length <= 240
        ? normalized
        : '${normalized.substring(0, 240)}…';
  }

  void dispose() {
    if (_ownsTransport) _transport.dispose();
  }
}
