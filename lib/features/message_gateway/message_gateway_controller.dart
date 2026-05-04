import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/model/app_info.dart';
import '../../app/state/settings_controller.dart';
import '../ai/ai_session_controller.dart';
import '../ai/model/ai_thread_template.dart';
import '../instructions/instructions_controller.dart';
import '../mcp/mcp_controller.dart';
import '../memory/memory_controller.dart';
import '../skills/skills_controller.dart';
import 'data/message_gateway_store.dart';
import 'model/web_message_platform_config.dart';
import 'service/web_message_platform_service.dart';

class WebGatewayModelOption {
  const WebGatewayModelOption({
    required this.key,
    required this.label,
    required this.providerId,
    required this.modelId,
  });

  final String key;
  final String label;
  final String providerId;
  final String modelId;
}

class MessageGatewayController extends ChangeNotifier {
  MessageGatewayController.uninitialized({
    required AiSessionController sessionController,
    required SettingsController settingsController,
    required SkillsController skillsController,
    required McpController mcpController,
    required MemoryController memoryController,
    required InstructionsController instructionsController,
    required AppInfo appInfo,
    MessageGatewayStore? store,
    WebMessagePlatformService? service,
  }) : _sessionController = sessionController,
       _settingsController = settingsController,
       _skillsController = skillsController,
       _mcpController = mcpController,
       _memoryController = memoryController,
       _store = store ?? MessageGatewayStore(),
       _service =
           service ??
           WebMessagePlatformService(
             sessionController: sessionController,
             settingsController: settingsController,
             skillsController: skillsController,
             mcpController: mcpController,
             memoryController: memoryController,
             instructionsController: instructionsController,
             appInfo: appInfo,
           ) {
    _logSub = _service.logStream.listen((_) => _scheduleLogNotify());
  }

  final AiSessionController _sessionController;
  final SettingsController _settingsController;
  final SkillsController _skillsController;
  final McpController _mcpController;
  final MemoryController _memoryController;
  final MessageGatewayStore _store;
  final WebMessagePlatformService _service;
  late final StreamSubscription<WebGatewayLogEntry> _logSub;
  Timer? _logNotifyTimer;

  WebMessagePlatformConfig _config = const WebMessagePlatformConfig();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  WebGatewayHealthResult? _lastHealthResult;
  final ValueNotifier<int> saveSuccessSignal = ValueNotifier<int>(0);

  WebMessagePlatformConfig get config => _config;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  WebGatewayHealthResult? get lastHealthResult => _lastHealthResult;
  WebGatewayRuntimeState get runtimeState => _service.state;
  bool get isRunning => _service.isRunning;
  String get webUrl => _service.boundUrl;
  List<WebGatewayLogEntry> get logs => _service.logs;
  WebGatewayRuntimeSnapshot runtimeSnapshot() => _service.runtimeSnapshot();
  Future<WebGatewayRuntimeSnapshot> refreshRuntimeSnapshot() async {
    final snapshot = await _service.runtimeSnapshotAsync();
    notifyListeners();
    return snapshot;
  }

  List<AiThreadTemplate> get templates => _sessionController.templates;
  List<String> get skillNames => _skillsController.skills
      .map((skill) => skill.name)
      .where((name) => name.trim().isNotEmpty)
      .toList(growable: false);
  List<String> get mcpServerNames => _mcpController.servers
      .map((server) => server.name)
      .where((name) => name.trim().isNotEmpty)
      .toList(growable: false);
  List<String> get memoryIds => _memoryController.entries
      .map((entry) => entry.id)
      .where((id) => id.trim().isNotEmpty)
      .toList(growable: false);
  List<String> get builtinToolNames => _settingsController.builtinToolConfigs
      .map((tool) => tool.effectiveName)
      .where((name) => name.trim().isNotEmpty)
      .toList(growable: false);
  List<WebGatewayModelOption> get modelOptions {
    final options = <WebGatewayModelOption>[];
    for (final provider in _settingsController.aiModels) {
      for (final modelId in provider.allModelIds) {
        final key = '${provider.id}::$modelId';
        options.add(
          WebGatewayModelOption(
            key: key,
            label: '${provider.providerLabel} / $modelId',
            providerId: provider.id,
            modelId: modelId,
          ),
        );
      }
    }
    return options;
  }

  Future<void> initialize() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final loaded = await _store.load();
      _config = _normalizeAgainstRuntimeOptions(loaded);
      if (_config.enabled) {
        await _service.start(_config);
      }
    } catch (error) {
      _errorMessage = '$error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveConfig(WebMessagePlatformConfig config) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    final normalized = _normalizeAgainstRuntimeOptions(config);
    try {
      await _store.save(normalized);
      final previous = _config;
      _config = normalized;
      await _applyRuntimeConfig(previous, normalized);
      saveSuccessSignal.value = saveSuccessSignal.value + 1;
    } catch (error) {
      _errorMessage = '$error';
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> startService() async {
    await saveConfig(_config.copyWith(enabled: true));
  }

  Future<void> stopService() async {
    await saveConfig(_config.copyWith(enabled: false));
  }

  Future<void> restartService() async {
    if (!_config.enabled) {
      await startService();
      return;
    }
    await _service.restart(_config);
    notifyListeners();
  }

  Future<void> reloadConfig() async {
    await _service.reloadConfig(_config);
    notifyListeners();
  }

  Future<void> hotFix() async {
    await _service.reloadConfig(_config);
    notifyListeners();
  }

  Future<WebGatewayHealthResult> runHealthCheck() async {
    final result = await _service.runHealthCheck();
    _lastHealthResult = result;
    notifyListeners();
    return result;
  }

  void updateTheme(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    _service.updateTheme(
      WebGatewayThemeSnapshot(
        primary: _hex(colorScheme.primary),
        onPrimary: _hex(colorScheme.onPrimary),
        surface: _hex(colorScheme.surface),
        surfaceContainer: _hex(colorScheme.surfaceContainerHighest),
        onSurface: _hex(colorScheme.onSurface),
        onSurfaceVariant: _hex(colorScheme.onSurfaceVariant),
        outline: _hex(colorScheme.outlineVariant),
        error: _hex(colorScheme.error),
        brightness: colorScheme.brightness.name,
      ),
    );
  }

  Future<void> _applyRuntimeConfig(
    WebMessagePlatformConfig previous,
    WebMessagePlatformConfig next,
  ) async {
    final endpointChanged =
        previous.listenHost != next.listenHost ||
        previous.listenPort != next.listenPort ||
        previous.enabled != next.enabled;
    if (!next.enabled) {
      await _service.stop();
      return;
    }
    if (!_service.isRunning) {
      await _service.start(next);
      return;
    }
    if (endpointChanged) {
      await _service.restart(next);
      return;
    }
    await _service.reloadConfig(next);
  }

  WebMessagePlatformConfig _normalizeAgainstRuntimeOptions(
    WebMessagePlatformConfig value,
  ) {
    final templateIds = templates.map((item) => item.id).toSet();
    final skills = skillNames.toSet();
    final mcpServers = mcpServerNames.toSet();
    final memories = memoryIds.toSet();
    final tools = builtinToolNames.toSet();
    final models = modelOptions.map((item) => item.key).toSet();
    List<String> keep(List<String> source, Set<String> allowed) {
      if (source.isEmpty) return const <String>[];
      return source.where(allowed.contains).toList(growable: false);
    }

    return value.copyWith(
      allowedTemplateIds: keep(value.allowedTemplateIds, templateIds),
      allowedSkillNames: keep(value.allowedSkillNames, skills),
      allowedMcpServerNames: keep(value.allowedMcpServerNames, mcpServers),
      allowedMemoryIds: keep(value.allowedMemoryIds, memories),
      allowedBuiltinToolNames: keep(value.allowedBuiltinToolNames, tools),
      allowedModelKeys: keep(value.allowedModelKeys, models),
    );
  }

  void _scheduleLogNotify() {
    if (_logNotifyTimer != null) return;
    _logNotifyTimer = Timer(const Duration(milliseconds: 120), () {
      _logNotifyTimer = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _logNotifyTimer?.cancel();
    _logSub.cancel();
    saveSuccessSignal.dispose();
    unawaited(_service.dispose());
    super.dispose();
  }

  String _hex(Color color) {
    final value = color.toARGB32();
    final rgb = value & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
