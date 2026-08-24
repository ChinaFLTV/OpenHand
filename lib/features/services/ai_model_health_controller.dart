import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:uuid/uuid.dart';

import '../../app/support/silent_log.dart';
import '../../app/support/system_proxy.dart';
import '../../shared/net/http_response_utils.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/timer_safety.dart';
import '../ai/index.dart';
import 'data/ai_model_health_store.dart';
import 'model/ai_exposure_models.dart';
import 'model/ai_model_health.dart';
import 'service/ai_exposure_proxy_client.dart';

typedef AiModelHealthProxyResolver =
    AiExposureProxyEndpoint? Function({required String targetHost});

const Duration _kModelHealthRequestTimeout = Duration(seconds: 20);
const Duration _kModelHealthConnectionTimeout = Duration(seconds: 15);
const int _kModelHealthMaxResponseBytes = kBytesPerMiB;

/// 一次显式模型巡检的取消状态；取消时主动关闭本轮创建的客户端。
class AiModelHealthCancellation {
  bool cancelled = false;
  final Set<http.Client> clients = <http.Client>{};
  final Completer<void> _signal = Completer<void>();

  Future<void> get whenCancelled => _signal.future;

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    _signal.complete();
    for (final client in clients.toList(growable: false)) {
      client.close();
    }
  }
}

class AiModelHealthController extends ChangeNotifier {
  AiModelHealthController({AiModelHealthStore? store})
    : _store = store ?? AiModelHealthStore();

  final AiModelHealthStore _store;
  final List<AiModelHealthRecord> _records = <AiModelHealthRecord>[];
  AiModelHealthSettings _settings = const AiModelHealthSettings();
  List<AiModelConfig> Function()? _modelsProvider;
  AiModelHealthProxyResolver? _proxyResolver;
  final Set<http.Client> _activeClients = <http.Client>{};
  Timer? _timer;
  bool _checking = false;
  bool _cancelling = false;
  bool _manualChecking = false;
  AiModelHealthCancellation? _activeCancellation;
  final Set<String> _checkingProviderIds = <String>{};
  bool _disposed = false;

  AiModelHealthSettings get settings => _settings;
  List<AiModelHealthRecord> get records =>
      List<AiModelHealthRecord>.unmodifiable(_records);
  bool get checking => _checking;
  bool get cancelling => _cancelling;
  bool get manualChecking => _checking && _manualChecking;

  bool isProviderChecking(String providerId) {
    return _checkingProviderIds.contains(providerId.trim());
  }

  bool isProviderManuallyChecking(String providerId) {
    return manualChecking && isProviderChecking(providerId);
  }

  Future<void> load() async {
    final loaded = await _store.loadSettings();
    _settings = loaded.copyWith(
      useSystemProxy:
          loaded.requestMode == AiModelHealthRequestMode.systemProxy,
    );
    _records
      ..clear()
      ..addAll(await _store.loadRecent());
    _restartTimer();
    notifyListeners();
  }

  void attachModelsProvider(List<AiModelConfig> Function() provider) {
    _modelsProvider = provider;
    _restartTimer();
  }

  void attachProxyResolver(AiModelHealthProxyResolver resolver) {
    _proxyResolver = resolver;
  }

  Future<bool> updateSettings({
    bool? enabled,
    int? intervalMinutes,
    int? concurrency,
    bool? useSystemProxy,
    AiModelHealthRequestMode? requestMode,
    int? retentionDays,
  }) async {
    var next = _settings.copyWith(
      enabled: enabled,
      intervalMinutes: intervalMinutes,
      concurrency: concurrency,
      useSystemProxy: useSystemProxy,
      requestMode: requestMode,
      retentionDays: retentionDays,
    );
    if (requestMode != null) {
      next = next.copyWith(
        useSystemProxy: requestMode == AiModelHealthRequestMode.systemProxy,
      );
    } else if (useSystemProxy != null) {
      next = next.copyWith(
        useSystemProxy: useSystemProxy,
        requestMode: useSystemProxy
            ? AiModelHealthRequestMode.systemProxy
            : AiModelHealthRequestMode.direct,
      );
    }
    if (next == _settings) return true;
    try {
      await _store.saveSettings(next);
      _settings = next;
      _restartTimer();
      notifyListeners();
      unawaited(
        _store.prune(next.retentionDays).catchError((
          Object error,
          StackTrace stack,
        ) {
          silentLog('ai_model_health_controller', '清理过期模型巡检记录', error, stack);
        }),
      );
      return true;
    } catch (error, stack) {
      silentLog('ai_model_health_controller', '保存模型巡检设置', error, stack);
      return false;
    }
  }

  List<AiModelHealthRecord> recordsFor(String providerId, String modelId) {
    final provider = providerId.trim();
    final model = modelId.trim();
    final values =
        _records
            .where(
              (record) =>
                  record.providerConfigId == provider &&
                  record.modelId == model,
            )
            .toList(growable: false)
          ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
    return values.take(36).toList(growable: false);
  }

  AiModelHealthRecord? latestFor(String providerId, String modelId) {
    final values = recordsFor(providerId, modelId);
    return values.isEmpty ? null : values.first;
  }

  Future<void> checkAll({bool manual = true}) async {
    if (_checking || _disposed) return;
    final models = _modelsProvider?.call() ?? const <AiModelConfig>[];
    if (models.isEmpty) return;
    await _checkProviders(models, manual: manual);
  }

  Future<void> checkProvider(AiModelConfig provider) async {
    if (_checking || _disposed) return;
    await _checkProviders(<AiModelConfig>[provider], manual: true);
  }

  Future<void> _checkProviders(
    Iterable<AiModelConfig> providers, {
    required bool manual,
  }) async {
    if (_checking || _disposed) return;
    final providerList = providers.toList(growable: false);
    final cancellation = AiModelHealthCancellation();
    _activeCancellation = cancellation;
    _checking = true;
    _cancelling = false;
    _manualChecking = manual;
    _checkingProviderIds
      ..clear()
      ..addAll(providerList.map((provider) => provider.id.trim()));
    notifyListeners();
    try {
      final pending = <Future<AiModelHealthRecord?>>[];
      for (final provider in providerList) {
        for (final modelId in _healthModelIds(provider)) {
          if (_disposed || cancellation.cancelled) return;
          pending.add(
            checkModel(
              provider,
              modelId: modelId,
              notify: false,
              cancellation: cancellation,
            ),
          );
          if (pending.length >= _settings.concurrency) {
            await Future.wait(pending);
            pending.clear();
          }
        }
      }
      if (pending.isNotEmpty) await Future.wait(pending);
    } finally {
      _checking = false;
      _cancelling = false;
      _manualChecking = false;
      cancellation.clients.clear();
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
      _checkingProviderIds.clear();
      if (!_disposed) notifyListeners();
    }
  }

  /// 停止当前显式触发的批量或提供商巡检。
  void cancelCheck() {
    if (!_checking || _cancelling || _disposed) return;
    _cancelling = true;
    _activeCancellation?.cancel();
    notifyListeners();
  }

  Future<AiModelHealthRecord?> checkModel(
    AiModelConfig provider, {
    String? modelId,
    bool notify = true,
    AiModelHealthCancellation? cancellation,
  }) async {
    if (_disposed || cancellation?.cancelled == true) return null;
    final selectedModelId = (modelId ?? provider.modelId).trim();
    if (selectedModelId.isEmpty) return null;
    final model = provider.copyWith(modelId: selectedModelId);
    final stopwatch = Stopwatch()..start();
    final uri = Uri.tryParse(model.normalizedBaseUrl);
    final mode = _effectiveMode;
    var success = false;
    var status = 'failed';
    int? responseCode;
    var errorMessage = '';
    final modelKind = _modelKind(provider, selectedModelId);
    String? requestUrl;
    String? requestMethod;
    int? requestDurationMs;
    try {
      if (_isTextModel(model, selectedModelId)) {
        final client = _createClient(
          mode,
          uri?.host ?? '',
          cancellation: cancellation,
        );
        final service = AiChatService(client: client);
        try {
          final result = await _awaitCancellation(
            service.testModel(model),
            cancellation,
          );
          success = true;
          status = 'healthy';
          responseCode = 200;
          requestUrl = result.requestUrl;
          requestMethod = result.requestMethod;
          requestDurationMs = result.durationMs;
        } on AiChatException catch (error) {
          errorMessage = error.message;
          responseCode = error.statusCode;
          status = 'unhealthy';
          requestUrl = error.telemetry?.requestUrl;
          requestMethod = error.telemetry?.requestMethod;
          requestDurationMs = error.telemetry?.durationMs;
        } finally {
          service.dispose();
          _closeClient(client);
        }
      } else {
        final client = _createClient(
          mode,
          uri?.host ?? '',
          cancellation: cancellation,
        );
        try {
          final target = _modelProbeUri(model, selectedModelId);
          requestUrl = target.toString();
          requestMethod = 'GET';
          final headers = _headers(model);
          var request = http.Request('GET', target)..headers.addAll(headers);
          var response = await _awaitCancellation(
            client.send(request).timeout(_kModelHealthRequestTimeout),
            cancellation,
          );
          responseCode = response.statusCode;
          await _awaitCancellation(_drainProbeResponse(response), cancellation);
          success = response.statusCode >= 200 && response.statusCode < 300;
          if (!success &&
              (response.statusCode == 404 || response.statusCode == 405)) {
            final operationPath = switch (modelKind) {
              'embedding' => 'embeddings',
              'moderation' => 'moderations',
              'image_edit' => 'images/edits',
              'image' => 'images/generations',
              'video' => 'videos/generations',
              'audio' => 'audio/speech',
              'transcription' => 'audio/transcriptions',
              'translation' => 'audio/translations',
              'rerank' => 'rerank',
              _ => 'models/${Uri.encodeComponent(selectedModelId)}',
            };
            if (_requiresSafeCapabilityProbe(modelKind)) {
              request = http.Request(
                'OPTIONS',
                _appendBasePath(model, operationPath),
              )..headers.addAll(headers);
              requestUrl = request.url.toString();
              requestMethod = 'OPTIONS';
              response = await _awaitCancellation(
                client.send(request).timeout(_kModelHealthRequestTimeout),
                cancellation,
              );
              responseCode = response.statusCode;
              await _awaitCancellation(
                _drainProbeResponse(response),
                cancellation,
              );
              success = response.statusCode >= 200 && response.statusCode < 300;
              status = success ? 'healthy' : 'unhealthy';
              if (!success) errorMessage = 'HTTP $responseCode';
              // OPTIONS 不会触发生成或转码，避免巡检产生实际费用。
            } else {
              final body = switch (modelKind) {
                'embedding' => <String, Object?>{
                  'model': selectedModelId,
                  'input': <String>['health check'],
                },
                'moderation' => <String, Object?>{
                  'model': selectedModelId,
                  'input': 'health check',
                },
                'image' || 'image_edit' || 'video' => <String, Object?>{
                  'model': selectedModelId,
                  'prompt': 'health check',
                },
                'audio' => <String, Object?>{
                  'model': selectedModelId,
                  'input': 'health check',
                },
                'transcription' ||
                'translation' => <String, Object?>{'model': selectedModelId},
                'rerank' => <String, Object?>{
                  'model': selectedModelId,
                  'query': 'health check',
                  'documents': <String>['health check'],
                },
                _ => <String, Object?>{'model': selectedModelId},
              };
              request =
                  http.Request('POST', _appendBasePath(model, operationPath))
                    ..headers.addAll(<String, String>{
                      ...headers,
                      'content-type': 'application/json',
                    })
                    ..body = jsonEncode(body);
              requestUrl = request.url.toString();
              requestMethod = 'POST';
              response = await _awaitCancellation(
                client.send(request).timeout(_kModelHealthRequestTimeout),
                cancellation,
              );
              responseCode = response.statusCode;
              await _awaitCancellation(
                _drainProbeResponse(response),
                cancellation,
              );
              success = response.statusCode >= 200 && response.statusCode < 300;
            }
          }
          status = success ? 'healthy' : 'unhealthy';
          if (!success) errorMessage = 'HTTP $responseCode';
        } finally {
          _closeClient(client);
        }
      }
    } catch (error) {
      if (cancellation?.cancelled == true) return null;
      errorMessage = '$error';
      status = 'error';
    }
    stopwatch.stop();
    if (_disposed || cancellation?.cancelled == true) return null;
    requestDurationMs ??= stopwatch.elapsedMilliseconds;
    final checkedAt = DateTime.now().toUtc();
    final record = AiModelHealthRecord(
      id: const Uuid().v4(),
      providerConfigId: provider.id,
      providerName: provider.providerLabel,
      modelId: selectedModelId,
      checkedAt: checkedAt,
      success: success,
      status: status,
      latencyMs: stopwatch.elapsedMilliseconds,
      durationMs: stopwatch.elapsedMilliseconds,
      requestMode: mode,
      responseCode: responseCode,
      host: uri?.host ?? '',
      port: uri?.hasPort == true ? uri?.port : null,
      modelKind: modelKind,
      errorMessage: errorMessage,
      metadata: <String, Object?>{
        'protocol': model.protocolType.storageValue,
        'api_dialect': model.apiDialect.storageValue,
        'auth_scheme': model.authScheme.storageValue,
        'model_kind': modelKind,
        'model_modalities': model
            .profileFor(selectedModelId)
            .supportedModalities
            .map((item) => item.storageValue)
            .toList(growable: false),
        'base_url': model.normalizedBaseUrl,
        'request_url': requestUrl ?? '',
        'request_method': requestMethod ?? '',
        'request_duration_ms': requestDurationMs,
        'probe_type': _probeType(modelKind, requestMethod),
        'proxy_endpoint': _proxyEndpointFor(mode, uri?.host ?? ''),
        'platform': Platform.operatingSystem,
        'platform_version': Platform.operatingSystemVersion,
        'dart_version': Platform.version.split(' ').first,
        'checked_at_utc': checkedAt.toIso8601String(),
      },
    );
    _records.insert(0, record);
    if (_records.length > 4000) _records.removeRange(4000, _records.length);
    try {
      await _store.insert(record);
    } catch (error, stack) {
      // 网络结果仍保留在当前会话，数据库异常不阻断巡检队列。
      silentLog('ai_model_health_controller', '保存模型巡检记录', error, stack);
    }
    if (notify && !_disposed) notifyListeners();
    return record;
  }

  AiModelHealthRequestMode get _effectiveMode {
    if (_settings.useSystemProxy &&
        _settings.requestMode == AiModelHealthRequestMode.direct) {
      return AiModelHealthRequestMode.systemProxy;
    }
    return _settings.requestMode;
  }

  List<String> _healthModelIds(AiModelConfig provider) {
    return AiModelConfig.normalizeModelIds(<String>[
      ...provider.allModelIds,
      provider.operationRouting.chatModelId ?? '',
      provider.operationRouting.responsesModelId ?? '',
      provider.operationRouting.completionModelId ?? '',
      provider.operationRouting.embeddingModelId ?? '',
      provider.operationRouting.moderationModelId ?? '',
      provider.operationRouting.rerankModelId ?? '',
      provider.operationRouting.imageModelId ?? '',
      provider.operationRouting.imageEditModelId ?? '',
      provider.operationRouting.videoModelId ?? '',
      provider.operationRouting.speechModelId ?? '',
      provider.operationRouting.transcriptionModelId ?? '',
      provider.operationRouting.translationModelId ?? '',
      provider.operationRouting.realtimeModelId ?? '',
    ]);
  }

  bool _isTextModel(AiModelConfig model, String modelId) {
    if (_modelKind(model, modelId) != 'text') return false;
    final profile = model.profileFor(modelId);
    if (profile.supportedModalities.contains(AiModelModality.text) ||
        profile.supportedModalities.isEmpty) {
      return !profile.capabilities.any(
        (capability) =>
            capability != AiModelCapability.embeddingGeneration &&
            capability != AiModelCapability.rerank &&
            capability != AiModelCapability.imageGeneration &&
            capability != AiModelCapability.videoGeneration &&
            capability != AiModelCapability.audioGeneration &&
            capability != AiModelCapability.readerConversion,
      );
    }
    return false;
  }

  String _modelKind(AiModelConfig provider, String modelId) {
    final routing = provider.operationRouting;
    if (routing.transcriptionModelId == modelId) return 'transcription';
    if (routing.translationModelId == modelId) return 'translation';
    if (routing.speechModelId == modelId) return 'audio';
    if (routing.moderationModelId == modelId) return 'moderation';
    if (routing.realtimeModelId == modelId) return 'realtime';
    if (routing.embeddingModelId == modelId) return 'embedding';
    if (routing.rerankModelId == modelId) return 'rerank';
    if (routing.imageEditModelId == modelId) return 'image_edit';
    if (routing.imageModelId == modelId) {
      return 'image';
    }
    if (routing.videoModelId == modelId) return 'video';
    final profile = provider.profileFor(modelId);
    if (profile.capabilities.contains(AiModelCapability.embeddingGeneration)) {
      return 'embedding';
    }
    if (profile.capabilities.contains(AiModelCapability.imageGeneration)) {
      return 'image';
    }
    if (profile.capabilities.contains(AiModelCapability.videoGeneration)) {
      return 'video';
    }
    if (profile.capabilities.contains(AiModelCapability.audioGeneration)) {
      return 'audio';
    }
    if (profile.capabilities.contains(AiModelCapability.pdfGeneration) ||
        profile.capabilities.contains(AiModelCapability.pptGeneration) ||
        profile.capabilities.contains(AiModelCapability.readerConversion)) {
      return 'document';
    }
    if (profile.capabilities.contains(AiModelCapability.rerank)) {
      return 'rerank';
    }
    return 'text';
  }

  Uri _modelProbeUri(AiModelConfig model, String modelId) {
    final base = Uri.parse(model.normalizedBaseUrl);
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: '${path}models/${Uri.encodeComponent(modelId)}');
  }

  Uri _appendBasePath(AiModelConfig model, String suffix) {
    final base = Uri.parse(model.normalizedBaseUrl);
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: '$path$suffix');
  }

  Map<String, String> _headers(AiModelConfig model) {
    final headers = <String, String>{...model.customHeaders};
    final token = model.token.trim();
    if (token.isNotEmpty) {
      switch (model.authScheme) {
        case AiAuthScheme.bearer:
        case AiAuthScheme.token:
          headers['Authorization'] = 'Bearer $token';
        case AiAuthScheme.apiKey:
          headers['x-api-key'] = token;
        case AiAuthScheme.none:
          break;
      }
    }
    return headers;
  }

  http.Client _createClient(
    AiModelHealthRequestMode mode,
    String host, {
    AiModelHealthCancellation? cancellation,
  }) {
    if (_disposed) throw StateError('模型健康巡检控制器已释放。');
    final http.Client client;
    if (mode == AiModelHealthRequestMode.systemProxy) {
      client = SystemProxyResolver.instance.createHttpClient();
    } else {
      final raw = HttpClient()
        ..connectionTimeout = _kModelHealthConnectionTimeout;
      try {
        if (mode == AiModelHealthRequestMode.direct) {
          raw.findProxy = (_) => 'DIRECT';
        } else {
          final endpoint = _proxyResolver?.call(targetHost: host);
          final proxyUri = endpoint == null ? null : Uri.tryParse(endpoint.url);
          if (proxyUri == null) {
            raw.findProxy = (_) => 'DIRECT';
          } else {
            configureAiExposureProxyHttpClient(raw, proxyUri);
          }
        }
        client = IOClient(raw);
      } on Object {
        raw.close(force: true);
        rethrow;
      }
    }
    _activeClients.add(client);
    cancellation?.clients.add(client);
    return client;
  }

  void _closeClient(http.Client client) {
    _activeClients.remove(client);
    _activeCancellation?.clients.remove(client);
    client.close();
  }

  Future<void> _drainProbeResponse(http.StreamedResponse response) {
    return drainByteStreamWithTimeout(
      response.stream,
      maxBytes: _kModelHealthMaxResponseBytes,
      idleTimeout: _kModelHealthRequestTimeout,
      totalTimeout: _kModelHealthRequestTimeout,
    );
  }

  Future<T> _awaitCancellation<T>(
    Future<T> operation,
    AiModelHealthCancellation? cancellation,
  ) {
    final activeCancellation = cancellation;
    if (activeCancellation == null) return operation;
    return Future.any<T>([
      operation,
      activeCancellation.whenCancelled.then<T>(
        (_) => throw const _AiModelHealthCancelledException(),
      ),
    ]);
  }

  String _proxyEndpointFor(AiModelHealthRequestMode mode, String host) {
    if (mode == AiModelHealthRequestMode.direct) return '';
    if (mode == AiModelHealthRequestMode.systemProxy) {
      final route = SystemProxyResolver.instance.resolveRuntimeRoute();
      return _maskedProxyEndpoint(route.httpsProxy ?? route.httpProxy);
    }
    return _proxyResolver?.call(targetHost: host)?.maskedUrl ?? '';
  }

  String _maskedProxyEndpoint(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '';
    final normalized = value.contains('://') ? value : 'http://$value';
    return maskAiExposureProxyUrl(normalized, fallback: '');
  }

  String _probeType(String modelKind, String? requestMethod) {
    if (requestMethod == 'GET') return 'model_metadata';
    return switch (modelKind) {
      'embedding' => 'embedding_minimal_input',
      'moderation' => 'moderation_minimal_input',
      'rerank' => 'rerank_minimal_input',
      'image' || 'image_edit' || 'video' => 'generation_minimal_prompt',
      'audio' => 'speech_minimal_input',
      'transcription' => 'transcription_capability',
      'translation' => 'translation_capability',
      'document' => 'document_capability',
      'realtime' => 'realtime_model_metadata',
      _ => 'text_availability_probe',
    };
  }

  bool _requiresSafeCapabilityProbe(String modelKind) {
    return switch (modelKind) {
      'image' ||
      'image_edit' ||
      'video' ||
      'audio' ||
      'transcription' ||
      'translation' ||
      'document' ||
      'realtime' => true,
      _ => false,
    };
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_settings.enabled && _modelsProvider != null) {
      _timer = startSafePeriodicTimer(
        Duration(minutes: _settings.intervalMinutes),
        (_) => checkAll(manual: false),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final client in _activeClients.toList(growable: false)) {
      client.close();
    }
    _activeClients.clear();
    _activeCancellation?.cancel();
    _activeCancellation = null;
    _checkingProviderIds.clear();
    super.dispose();
  }
}

class _AiModelHealthCancelledException implements Exception {
  const _AiModelHealthCancelledException();
}
