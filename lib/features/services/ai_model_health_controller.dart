import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:uuid/uuid.dart';

import '../../app/support/system_proxy.dart';
import '../../shared/util/timer_safety.dart';
import '../ai/index.dart';
import 'data/ai_model_health_store.dart';
import 'model/ai_exposure_models.dart';
import 'model/ai_model_health.dart';

typedef AiModelHealthProxyResolver =
    AiExposureProxyEndpoint? Function({required String targetHost});

class AiModelHealthController extends ChangeNotifier {
  AiModelHealthController({AiModelHealthStore? store})
    : _store = store ?? AiModelHealthStore();

  final AiModelHealthStore _store;
  final List<AiModelHealthRecord> _records = <AiModelHealthRecord>[];
  AiModelHealthSettings _settings = const AiModelHealthSettings();
  List<AiModelConfig> Function()? _modelsProvider;
  AiModelHealthProxyResolver? _proxyResolver;
  Timer? _timer;
  bool _checking = false;
  bool _disposed = false;

  AiModelHealthSettings get settings => _settings;
  List<AiModelHealthRecord> get records =>
      List<AiModelHealthRecord>.unmodifiable(_records);
  bool get checking => _checking;

  Future<void> load() async {
    _settings = await _store.loadSettings();
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
    bool? useSystemProxy,
    AiModelHealthRequestMode? requestMode,
    int? retentionDays,
  }) async {
    final next = _settings.copyWith(
      enabled: enabled,
      intervalMinutes: intervalMinutes,
      useSystemProxy: useSystemProxy,
      requestMode: requestMode,
      retentionDays: retentionDays,
    );
    if (next == _settings) return true;
    try {
      await _store.saveSettings(next);
      _settings = next;
      _restartTimer();
      notifyListeners();
      unawaited(_store.prune(next.retentionDays));
      return true;
    } catch (_) {
      return false;
    }
  }

  List<AiModelHealthRecord> recordsFor(String providerId, String modelId) {
    final provider = providerId.trim();
    final model = modelId.trim();
    return _records
        .where(
          (record) =>
              record.providerConfigId == provider && record.modelId == model,
        )
        .take(36)
        .toList(growable: false);
  }

  AiModelHealthRecord? latestFor(String providerId, String modelId) {
    final values = recordsFor(providerId, modelId);
    return values.isEmpty ? null : values.first;
  }

  Future<void> checkAll() async {
    if (_checking || _disposed) return;
    final models = _modelsProvider?.call() ?? const <AiModelConfig>[];
    if (models.isEmpty) return;
    _checking = true;
    notifyListeners();
    try {
      final pending = <Future<AiModelHealthRecord?>>[];
      for (final provider in models) {
        for (final modelId in provider.allModelIds) {
          if (_disposed) return;
          pending.add(checkModel(provider, modelId: modelId, notify: false));
          if (pending.length >= 4) {
            await Future.wait(pending);
            pending.clear();
          }
        }
      }
      if (pending.isNotEmpty) await Future.wait(pending);
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<AiModelHealthRecord?> checkModel(
    AiModelConfig provider, {
    String? modelId,
    bool notify = true,
  }) async {
    if (_disposed) return null;
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
    var modelKind = _modelKind(model);
    try {
      if (_isTextModel(model)) {
        final client = _createClient(mode, uri?.host ?? '');
        final service = AiChatService(client: client);
        try {
          await service.testModel(model);
          success = true;
          status = 'healthy';
          responseCode = 200;
        } on AiChatException catch (error) {
          errorMessage = error.message;
          responseCode = error.statusCode;
        } finally {
          service.dispose();
          client.close();
        }
      } else {
        final client = _createClient(mode, uri?.host ?? '');
        try {
          final target = _modelProbeUri(model, selectedModelId);
          final headers = _headers(model);
          var request = http.Request('GET', target)..headers.addAll(headers);
          var response = await client
              .send(request)
              .timeout(const Duration(seconds: 20));
          responseCode = response.statusCode;
          await response.stream.drain();
          success = response.statusCode >= 200 && response.statusCode < 300;
          if (!success &&
              (response.statusCode == 404 || response.statusCode == 405)) {
            final operationPath = switch (modelKind) {
              'embedding' => 'embeddings',
              'image' => 'images/generations',
              'video' => 'videos/generations',
              'audio' => 'audio/speech',
              _ => 'models/${Uri.encodeComponent(selectedModelId)}',
            };
            final body = switch (modelKind) {
              'embedding' => <String, Object?>{
                'model': selectedModelId,
                'input': <String>['health check'],
              },
              'image' || 'video' => <String, Object?>{
                'model': selectedModelId,
                'prompt': 'health check',
              },
              'audio' => <String, Object?>{
                'model': selectedModelId,
                'input': 'health check',
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
            response = await client
                .send(request)
                .timeout(const Duration(seconds: 20));
            responseCode = response.statusCode;
            await response.stream.drain();
            success = response.statusCode >= 200 && response.statusCode < 300;
          }
          status = success ? 'healthy' : 'unhealthy';
          if (!success) errorMessage = 'HTTP $responseCode';
        } finally {
          client.close();
        }
      }
    } catch (error) {
      errorMessage = '$error';
      status = 'error';
    }
    stopwatch.stop();
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
        'base_url': model.normalizedBaseUrl,
      },
    );
    _records.insert(0, record);
    if (_records.length > 4000) _records.removeRange(4000, _records.length);
    try {
      await _store.insert(record);
    } catch (_) {
      // 网络结果仍保留在当前会话，数据库异常不阻断巡检队列。
    }
    if (notify) notifyListeners();
    return record;
  }

  AiModelHealthRequestMode get _effectiveMode {
    if (_settings.useSystemProxy &&
        _settings.requestMode == AiModelHealthRequestMode.direct) {
      return AiModelHealthRequestMode.systemProxy;
    }
    return _settings.requestMode;
  }

  bool _isTextModel(AiModelConfig model) {
    final profile = model.profileFor(model.modelId);
    if (profile.supportedModalities.contains(AiModelModality.text) ||
        profile.supportedModalities.isEmpty) {
      return !profile.capabilities.any(
        (capability) =>
            capability != AiModelCapability.embeddingGeneration &&
            capability != AiModelCapability.rerank &&
            capability != AiModelCapability.imageGeneration &&
            capability != AiModelCapability.videoGeneration &&
            capability != AiModelCapability.audioGeneration,
      );
    }
    return false;
  }

  String _modelKind(AiModelConfig model) {
    final profile = model.profileFor(model.modelId);
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

  http.Client _createClient(AiModelHealthRequestMode mode, String host) {
    if (mode == AiModelHealthRequestMode.systemProxy) {
      return SystemProxyResolver.instance.createHttpClient();
    }
    final raw = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    if (mode == AiModelHealthRequestMode.direct) {
      raw.findProxy = (_) => 'DIRECT';
    } else {
      final endpoint = _proxyResolver?.call(targetHost: host);
      final proxyUri = endpoint == null ? null : Uri.tryParse(endpoint.url);
      raw.findProxy = (_) => proxyUri == null
          ? 'DIRECT'
          : 'PROXY ${proxyUri.host}:${proxyUri.port}';
    }
    return IOClient(raw);
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_settings.enabled && _modelsProvider != null) {
      _timer = startSafePeriodicTimer(
        Duration(minutes: _settings.intervalMinutes),
        (_) => unawaited(checkAll()),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
