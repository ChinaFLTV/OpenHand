import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../shared/util/serial_task_queue.dart';
import '../ai/index.dart';
import 'data/ai_model_proxy_store.dart';
import 'model/ai_model_proxy_models.dart';

enum AiModelProxyLifecycle { stopped, starting, running, stopping, error }

class AiModelProxyController extends ChangeNotifier {
  AiModelProxyController({AiModelProxyStore? store})
    : _store = store ?? AiModelProxyStore();

  final AiModelProxyStore _store;
  final SerialTaskQueue _writes = SerialTaskQueue(maxPendingTasks: 2048);
  AiModelProxySettings _settings = const AiModelProxySettings();
  AiModelProxyLifecycle _lifecycle = AiModelProxyLifecycle.stopped;
  bool _busy = false;
  String? _errorMessage;
  bool _disposed = false;
  final Map<String, int> _roundRobinCursors = <String, int>{};
  final List<DateTime> _rateWindow = <DateTime>[];
  int _rateWindowTokens = 0;
  List<AiModelConfig> Function()? _modelsProvider;

  AiModelProxySettings get settings => _settings;
  AiModelProxyLifecycle get lifecycle => _lifecycle;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;

  void attachModelsProvider(List<AiModelConfig> Function() provider) {
    _modelsProvider = provider;
  }

  bool authorize(Map<String, String> headers) {
    if (!_settings.requireAuthentication) return true;
    final expected = _settings.apiKey.trim();
    if (expected.isEmpty) return false;
    final authorization = headers.entries
        .firstWhere(
          (entry) => entry.key.toLowerCase() == 'authorization',
          orElse: () => const MapEntry<String, String>('', ''),
        )
        .value
        .trim();
    final apiKey = headers.entries
        .firstWhere(
          (entry) => entry.key.toLowerCase() == 'x-api-key',
          orElse: () => const MapEntry<String, String>('', ''),
        )
        .value
        .trim();
    return apiKey == expected ||
        authorization == expected ||
        authorization == 'Bearer $expected';
  }

  AiModelProxyBackend? resolveBackend(String exposedModel) {
    final route = _settings.routes
        .where((item) => item.exposedModel == exposedModel)
        .firstOrNull;
    if (route == null) return null;
    final enabled = route.backends
        .where((item) => item.enabled)
        .toList(growable: false);
    if (enabled.isEmpty) return null;
    return switch (_settings.scheduling) {
      AiModelProxySchedulingStrategy.random =>
        enabled[math.Random().nextInt(enabled.length)],
      AiModelProxySchedulingStrategy.roundRobin => _nextRoundRobin(
        exposedModel,
        enabled,
      ),
      AiModelProxySchedulingStrategy.priority ||
      AiModelProxySchedulingStrategy.conservative ||
      AiModelProxySchedulingStrategy.sticky => enabled.first,
    };
  }

  List<String> get endpointPaths => switch (_settings.apiStyle) {
    AiModelProxyApiStyle.openAiChatCompletions => const <String>[
      '/v1/models',
      '/v1/chat/completions',
    ],
    AiModelProxyApiStyle.openAiResponses => const <String>[
      '/v1/models',
      '/v1/responses',
    ],
    AiModelProxyApiStyle.claude => const <String>['/v1/models', '/v1/messages'],
    AiModelProxyApiStyle.gemini => const <String>[
      '/v1/models',
      '/v1beta/models:generateContent',
    ],
  };

  bool consumeRateLimit({required int tokens}) {
    final now = DateTime.now();
    _rateWindow.removeWhere(
      (time) => now.difference(time) >= const Duration(minutes: 1),
    );
    if (_settings.limitMode == AiModelProxyLimitMode.rpm) {
      if (_rateWindow.length >= _settings.limitThreshold) return false;
      _rateWindow.add(now);
      return true;
    }
    final safeTokens = tokens.clamp(0, 1 << 30);
    if (_rateWindowTokens + safeTokens > _settings.limitThreshold) return false;
    _rateWindow.add(now);
    _rateWindowTokens += safeTokens;
    return true;
  }

  Future<void> load() async {
    _settings = await _store.load();
    _notify();
  }

  Future<void> toggle() =>
      _lifecycle == AiModelProxyLifecycle.running ? stop() : start();

  Future<void> start() async {
    if (_busy || _lifecycle == AiModelProxyLifecycle.running) return;
    _busy = true;
    _lifecycle = AiModelProxyLifecycle.starting;
    _errorMessage = null;
    _notify();
    try {
      _ensureRoutesFromProviders();
      if (_settings.routes.every(
        (route) => route.backends.every((item) => !item.enabled),
      )) {
        throw StateError('至少需要一个启用的后备模型。');
      }
      _settings = _settings.copyWith(enabled: true);
      await _store.save(_settings);
      _lifecycle = AiModelProxyLifecycle.running;
    } catch (error) {
      _lifecycle = AiModelProxyLifecycle.error;
      _errorMessage = '$error';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (_busy || _lifecycle == AiModelProxyLifecycle.stopped) return;
    _busy = true;
    _lifecycle = AiModelProxyLifecycle.stopping;
    _notify();
    try {
      _settings = _settings.copyWith(enabled: false);
      await _store.save(_settings);
      _lifecycle = AiModelProxyLifecycle.stopped;
    } catch (error) {
      _lifecycle = AiModelProxyLifecycle.error;
      _errorMessage = '$error';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> saveSettings(AiModelProxySettings settings) async {
    _settings = settings;
    _notify();
    await _writes.enqueue(() => _store.save(settings));
  }

  Future<void> saveRoutes(List<AiModelProxyRoute> routes) =>
      saveSettings(_settings.copyWith(routes: routes));

  Future<void> recordRequest({
    required bool success,
    required int tokens,
    required int durationMs,
    String providerId = '',
    String modelId = '',
    String apiStyle = '',
    String? error,
  }) => saveSettings(
    _settings.record(
      success: success,
      tokens: tokens,
      durationMs: durationMs,
      providerId: providerId,
      modelId: modelId,
      apiStyle: apiStyle,
      error: error,
    ),
  );

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  AiModelProxyBackend _nextRoundRobin(
    String exposedModel,
    List<AiModelProxyBackend> enabled,
  ) {
    final index = _roundRobinCursors.update(
      exposedModel,
      (value) => (value + 1) % enabled.length,
      ifAbsent: () => 0,
    );
    return enabled[index];
  }

  void _ensureRoutesFromProviders() {
    if (_settings.routes.isNotEmpty) return;
    final providers = _modelsProvider?.call() ?? const <AiModelConfig>[];
    final routes = <AiModelProxyRoute>[
      for (final provider in providers)
        for (final modelId in provider.allModelIds)
          AiModelProxyRoute(
            exposedModel: modelId,
            backends: <AiModelProxyBackend>[
              AiModelProxyBackend(providerId: provider.id, modelId: modelId),
            ],
          ),
    ];
    if (routes.isNotEmpty) {
      _settings = _settings.copyWith(routes: routes);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
