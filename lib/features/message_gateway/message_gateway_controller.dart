import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/state/settings_controller.dart';
import '../../app/support/silent_log.dart';
import '../../shared/core/managed_change_notifier.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/timer_safety.dart';
import '../agents/index.dart';
import '../ai/index.dart';
import '../instructions/index.dart';
import '../mcp/index.dart';
import '../memory/index.dart';
import '../plugin_service/index.dart';
import '../skills/index.dart';
import 'data/message_gateway_store.dart';
import 'data/web_gateway_ops_store.dart';
import 'dingtalk_message_gateway_controller.dart';
import 'message_gateway_dependencies.dart';
import 'message_gateway_errors.dart';
import 'model/web_message_platform_config.dart';
import 'service/web_message_platform_service.dart';

export 'service/web_message_platform_service.dart' show WebWriteApprovalRequest;

String _reportMessageGatewayFailure(
  String action,
  Object error,
  StackTrace stack, {
  String? fallback,
}) {
  silentLog('message_gateway', action, error, stack);
  return messageGatewayFailureMessage(
    error,
    fallback: fallback ?? '$action失败，请稍后重试。',
  );
}

class WebGatewayModelOption {
  const WebGatewayModelOption({
    required this.key,
    required this.label,
    required this.providerId,
    required this.providerLabel,
    required this.modelId,
  });

  final String key;
  final String label;
  final String providerId;
  final String providerLabel;
  final String modelId;
}

/// 单条用户指令在 Web 通用消息平台编辑弹窗里的展示项。
/// `id` 与持久化的 `allowedInstructionIds` 一一对应，`label` 用于 UI 渲染。
class WebGatewayInstructionOption {
  const WebGatewayInstructionOption({
    required this.id,
    required this.label,
    required this.enabled,
  });

  final String id;
  final String label;
  final bool enabled;
}

class WebGatewayAgentOption {
  const WebGatewayAgentOption({
    required this.id,
    required this.label,
    required this.subtitle,
  });

  final String id;
  final String label;
  final String subtitle;
}

class MessageGatewayController extends ManagedChangeNotifier {
  MessageGatewayController.uninitialized(
    MessageGatewayDependencies dependencies, {
    MessageGatewayStore? store,
    WebMessagePlatformService? service,
  }) : _sessionController = dependencies.sessionController,
       _settingsController = dependencies.settingsController,
       _agentsController = dependencies.agentsController,
       _skillsController = dependencies.skillsController,
       _mcpController = dependencies.mcpController,
       _memoryController = dependencies.memoryController,
       _instructionsController = dependencies.instructionsController,
       _store = store ?? MessageGatewayStore(),
       _service = service ?? WebMessagePlatformService(dependencies),
       _dingtalkController = DingTalkMessageGatewayController(dependencies) {
    _dingtalkController.writeApprovalHandler = (sessionId, request) {
      return requestWriteApproval(
        sessionId: sessionId,
        request: request,
        source: 'dingtalk_gateway',
      );
    };
    _logSub = _service.logStream.listen((_) => _scheduleLogNotify());
  }

  final AiSessionController _sessionController;
  final SettingsController _settingsController;
  final AgentsController _agentsController;
  final SkillsController _skillsController;
  final McpController _mcpController;
  final MemoryController _memoryController;
  final InstructionsController _instructionsController;
  final MessageGatewayStore _store;
  final WebMessagePlatformService _service;
  final DingTalkMessageGatewayController _dingtalkController;
  late final StreamSubscription<WebGatewayLogEntry> _logSub;
  Future<void>? _shutdownFuture;
  Future<void>? _resourceShutdownFuture;
  bool _disposed = false;
  late final OpenHandDebouncer _logNotifyDebouncer = OpenHandDebouncer(
    delay: _logNotifyDelay,
  );
  static const Duration _logNotifyDelay = Duration(milliseconds: 120);
  static const Duration runtimeCleanupTimeout =
      kOpenHandServiceRuntimeCleanupTimeout;

  @override
  Duration get operationShutdownTimeout => runtimeCleanupTimeout;

  WebMessagePlatformConfig _config = const WebMessagePlatformConfig();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  bool _hasTrustedSnapshot = false;
  bool _hasPendingRuntimeConfig = false;
  final ChangePulse _saveSuccessPulse = ChangePulse();
  static const Set<AiBuiltinToolKind> _knowledgeBaseBuiltinToolKinds =
      <AiBuiltinToolKind>{
        AiBuiltinToolKind.knowledgeSearch,
        AiBuiltinToolKind.knowledgeRead,
      };

  WebMessagePlatformConfig get config => _config;
  ValueListenable<int> get saveSuccessSignal => _saveSuccessPulse.listenable;
  bool get isLoading => _isLoading;
  bool get isOperating =>
      _isLoading ||
      _isSaving ||
      _service.state == WebGatewayRuntimeState.starting ||
      _service.state == WebGatewayRuntimeState.stopping;
  bool get hasPendingRuntimeConfig => _hasPendingRuntimeConfig;
  bool get hasTrustedSnapshot => _hasTrustedSnapshot;
  String? get errorMessage => _errorMessage;
  WebGatewayRuntimeState get runtimeState => _service.state;
  bool get isRunning => _service.isRunning;
  DingTalkMessageGatewayController get dingtalk => _dingtalkController;

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  String get webUrl => _service.boundUrl;
  Stream<List<WebWriteApprovalRequest>> get pendingWriteApprovalsStream =>
      _service.pendingWriteApprovalsStream;
  List<WebWriteApprovalRequest> get pendingWriteApprovals =>
      _service.pendingWriteApprovals;

  /// 当前可访问该 Web 服务的全部 URL（监听通配符地址时含 LAN IP）。
  /// view 与设置面板可直接 `Wrap`/`SelectableText.rich` 渲染。
  List<String> get webUrls => _service.accessibleUrls;
  List<WebGatewayLogEntry> get logs => _service.logs;
  List<WebGatewayRuntimeSnapshot> get persistedRuntimeSnapshots =>
      _service.persistedRuntimeSnapshots;
  List<WebGatewayCleanupResult> get cleanupHistory => _service.cleanupHistory;
  WebGatewayRuntimeSnapshot runtimeSnapshot() => _service.runtimeSnapshot();
  Future<WebGatewayRuntimeSnapshot> refreshRuntimeSnapshot() async {
    final snapshot = await _service.runtimeSnapshotAsync();
    notifyListeners();
    return snapshot;
  }

  Future<void> refreshAccessibleUrls({bool force = false}) async {
    if (_disposed || !_service.isRunning) return;
    final changed = await _service.refreshAccessibleUrls(force: force);
    if (changed && !_disposed) notifyListeners();
  }

  Future<BashCommandApprovalDecision> requestWriteApproval({
    required String sessionId,
    required BashCommandApprovalRequest request,
    String source = 'app',
  }) {
    return _service.requestWriteApproval(
      sessionId: sessionId,
      request: request,
      source: source,
    );
  }

  bool respondWriteApproval(
    String approvalId, {
    required BashCommandApprovalDecision decision,
    String source = 'app',
  }) {
    return _service.respondWriteApproval(
      approvalId,
      decision: decision,
      source: source,
    );
  }

  List<AiThreadTemplate> get templates => _sessionController.availableTemplates;
  List<String> get skillNames =>
      _cleanStringValues(_skillsController.skills.map((skill) => skill.name));
  List<String> get mcpServerNames => _cleanStringValues(
    _mcpController.runtimeServers.map((server) => server.name),
  );
  List<String> get memoryIds =>
      _cleanStringValues(_memoryController.entries.map((entry) => entry.id));
  List<String> get builtinToolNames => _cleanStringValues(
    _settingsController.builtinToolConfigs.map((tool) => tool.effectiveName),
  );
  List<String> get knowledgeBaseBuiltinToolNames => _cleanStringValues(
    _settingsController.builtinToolConfigs
        .where((tool) => _knowledgeBaseBuiltinToolKinds.contains(tool.kind))
        .map((tool) => tool.effectiveName),
  );
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
            providerLabel: provider.providerLabel,
            modelId: modelId,
          ),
        );
      }
    }
    return options;
  }

  /// 全部用户指令（含未启用），用于 Web 通用消息平台编辑弹窗的多选列表。
  /// `label` 优先使用指令名称，回退到 id；UI 据 `enabled` 渲染灰字副标题。
  List<WebGatewayInstructionOption> get instructionOptions {
    final result = <WebGatewayInstructionOption>[];
    for (final entry in _instructionsController.entries) {
      final id = entry.id.trim();
      if (id.isEmpty) continue;
      final name = entry.name.trim();
      result.add(
        WebGatewayInstructionOption(
          id: id,
          label: name.isEmpty ? id : name,
          enabled: entry.enabled,
        ),
      );
    }
    return result;
  }

  List<WebGatewayAgentOption> get agentOptions {
    final result = <WebGatewayAgentOption>[];
    for (final agent in _agentsController.enabledAgents) {
      final id = agent.id.trim();
      if (id.isEmpty) continue;
      final subtitle = <String>[
        agent.position.trim(),
        agent.department.trim(),
      ].where((item) => item.isNotEmpty).join(' · ');
      result.add(
        WebGatewayAgentOption(
          id: id,
          label: agent.name.trim().isEmpty ? id : agent.name.trim(),
          subtitle: subtitle,
        ),
      );
    }
    return result;
  }

  Future<void> initialize() {
    return enqueueOperation(_initializeLocked);
  }

  Future<void> _initializeLocked() async {
    _isLoading = true;
    _hasTrustedSnapshot = false;
    _errorMessage = null;
    notifyListeners();
    try {
      try {
        await _service.loadPersistedOpsData();
        final loaded = await _store.load();
        _config = _normalizeAgainstRuntimeOptions(loaded);
        _hasTrustedSnapshot = true;
        _hasPendingRuntimeConfig = false;
      } catch (error, stack) {
        _hasTrustedSnapshot = false;
        _errorMessage = _reportMessageGatewayFailure('加载消息网关配置', error, stack);
        return;
      }
      try {
        await _dingtalkController.initialize();
      } catch (error, stack) {
        silentLog('message_gateway', '初始化钉钉消息网关', error, stack);
      }
      if (_config.autoStartOnLaunch && !_service.isRunning) {
        final startupConfig = _config.copyWith(enabled: true);
        try {
          await _service.start(startupConfig);
          _config = startupConfig;
        } catch (error, stack) {
          _hasPendingRuntimeConfig = true;
          _errorMessage = _reportMessageGatewayFailure(
            '自动启动消息网关',
            error,
            stack,
            fallback: '消息网关自动启动失败，请检查监听地址与端口。',
          );
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveConfig(
    WebMessagePlatformConfig config, {
    bool forceRuntimeApply = false,
  }) {
    return enqueueOperation(
      () => _saveConfigLocked(config, forceRuntimeApply: forceRuntimeApply),
    );
  }

  Future<void> _saveConfigLocked(
    WebMessagePlatformConfig config, {
    bool forceRuntimeApply = false,
  }) async {
    if (!await _ensureTrustedSnapshotLocked()) {
      throw StateError('消息网关配置当前不可用。');
    }
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    final normalized = _normalizeAgainstRuntimeOptions(config);
    try {
      try {
        await _store.save(normalized);
      } catch (error, stack) {
        _hasTrustedSnapshot = false;
        _errorMessage = _reportMessageGatewayFailure('保存消息网关配置', error, stack);
        rethrow;
      }
      final previous = _config;
      _config = normalized;
      _hasTrustedSnapshot = true;
      if (forceRuntimeApply || normalized.autoReloadOnChange) {
        try {
          await _applyRuntimeConfig(previous, normalized);
          _hasPendingRuntimeConfig = false;
        } catch (error, stack) {
          _hasPendingRuntimeConfig = true;
          _errorMessage = _reportMessageGatewayFailure(
            '应用消息网关运行配置',
            error,
            stack,
            fallback: '消息网关运行配置应用失败，请检查监听地址与端口。',
          );
          rethrow;
        }
      } else {
        _hasPendingRuntimeConfig = _service.isRunning;
      }
      _saveSuccessPulse.emit();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> _ensureTrustedSnapshotLocked({bool forceReload = false}) async {
    if (_hasTrustedSnapshot && !forceReload) return true;
    try {
      _config = _normalizeAgainstRuntimeOptions(await _store.load());
      _hasTrustedSnapshot = true;
      _errorMessage = null;
      return true;
    } catch (error, stack) {
      _hasTrustedSnapshot = false;
      _errorMessage = _reportMessageGatewayFailure('重新加载消息网关配置', error, stack);
      notifyListeners();
      return false;
    }
  }

  Future<void> startService() {
    return enqueueOperation(
      () => _saveConfigLocked(
        _config.copyWith(enabled: true),
        forceRuntimeApply: true,
      ),
    );
  }

  Future<void> stopService() {
    return enqueueOperation(
      () => _saveConfigLocked(
        _config.copyWith(enabled: false),
        forceRuntimeApply: true,
      ),
    );
  }

  Future<void> restartService() {
    return enqueueOperation(_restartServiceLocked);
  }

  Future<void> _restartServiceLocked() async {
    if (!await _ensureTrustedSnapshotLocked(forceReload: true)) {
      throw StateError('消息网关配置当前不可用。');
    }
    if (!_config.enabled) {
      await _saveConfigLocked(
        _config.copyWith(enabled: true),
        forceRuntimeApply: true,
      );
      return;
    }
    await _service.restart(_config);
    _hasPendingRuntimeConfig = false;
    notifyListeners();
  }

  Future<void> reloadConfig() {
    return enqueueOperation(_reloadConfigLocked);
  }

  Future<void> _reloadConfigLocked() async {
    if (!await _ensureTrustedSnapshotLocked(forceReload: true)) {
      throw StateError('消息网关配置当前不可用。');
    }
    await _service.reloadConfig(_config);
    _hasPendingRuntimeConfig = false;
    notifyListeners();
  }

  Future<void> hotFix() {
    return enqueueOperation(_reloadConfigLocked);
  }

  Future<WebGatewayHealthResult> runHealthCheck() => _service.runHealthCheck();

  Future<WebGatewayConnectivityTestResult> runConnectivityTest() async {
    final result = await _service.runConnectivityTest();
    notifyListeners();
    return result;
  }

  Future<WebGatewayCleanupResult> cleanupLogs() async {
    final result = await _service.cleanupArtifacts(logs: true, uploads: false);
    notifyListeners();
    return result;
  }

  Future<WebGatewayCleanupResult> cleanupUploadCache() async {
    final result = await _service.cleanupArtifacts(logs: false, uploads: true);
    notifyListeners();
    return result;
  }

  Future<WebGatewayOpsPersistenceReport> measureOpsCache() {
    return enqueueOperation(_service.measurePersistedOpsData);
  }

  Future<WebGatewayOpsPersistenceReport> cleanupOpsCache({
    DateTime? startUtc,
    DateTime? endUtc,
  }) {
    return enqueueOperation(() async {
      final result = await _service.clearPersistedOpsData(
        startUtc: startUtc,
        endUtc: endUtc,
      );
      notifyListeners();
      return result;
    });
  }

  Future<WebGatewayCleanupResult> cleanupExpiredArtifacts() async {
    final result = await _service.cleanupArtifacts(
      logs: true,
      uploads: true,
      expiredOnly: true,
    );
    notifyListeners();
    return result;
  }

  Future<String> exportLogBundleJson() async {
    return _service.exportLogBundleJson();
  }

  Future<String> exportCurrentLogText() async {
    return _service.exportCurrentLogText();
  }

  void updateTheme(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    _service.updateTheme(
      WebGatewayThemeSnapshot(
        primary: _hex(colorScheme.primary),
        onPrimary: _hex(colorScheme.onPrimary),
        primaryContainer: _hex(colorScheme.primaryContainer),
        onPrimaryContainer: _hex(colorScheme.onPrimaryContainer),
        secondary: _hex(colorScheme.secondary),
        onSecondary: _hex(colorScheme.onSecondary),
        secondaryContainer: _hex(colorScheme.secondaryContainer),
        onSecondaryContainer: _hex(colorScheme.onSecondaryContainer),
        tertiary: _hex(colorScheme.tertiary),
        onTertiary: _hex(colorScheme.onTertiary),
        tertiaryContainer: _hex(colorScheme.tertiaryContainer),
        onTertiaryContainer: _hex(colorScheme.onTertiaryContainer),
        surface: _hex(colorScheme.surface),
        surfaceContainerLowest: _hex(colorScheme.surfaceContainerLowest),
        surfaceContainerLow: _hex(colorScheme.surfaceContainerLow),
        surfaceContainer: _hex(colorScheme.surfaceContainer),
        surfaceContainerHigh: _hex(colorScheme.surfaceContainerHigh),
        surfaceContainerHighest: _hex(colorScheme.surfaceContainerHighest),
        onSurface: _hex(colorScheme.onSurface),
        onSurfaceVariant: _hex(colorScheme.onSurfaceVariant),
        outline: _hex(colorScheme.outline),
        outlineVariant: _hex(colorScheme.outlineVariant),
        inverseSurface: _hex(colorScheme.inverseSurface),
        inverseOnSurface: _hex(colorScheme.onInverseSurface),
        error: _hex(colorScheme.error),
        errorContainer: _hex(colorScheme.errorContainer),
        onErrorContainer: _hex(colorScheme.onErrorContainer),
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
    final normalizedValue = value.normalized();
    final templateIds = templates.map((item) => item.id).toSet();
    final skills = skillNames.toSet();
    final mcpServers = mcpServerNames.toSet();
    final memories = memoryIds.toSet();
    final tools = builtinToolNames.toSet();
    final models = modelOptions.map((item) => item.key).toSet();
    final instructions = instructionOptions.map((item) => item.id).toSet();
    final agents = agentOptions.map((item) => item.id).toSet();
    final allowedToolNames = normalizedValue.knowledgeBaseEnabled
        ? normalizedValue.allowedBuiltinToolNames
        : _withoutKnowledgeBaseBuiltinToolNames(
            normalizedValue.allowedBuiltinToolNames,
          );
    List<String> keep(List<String> source, Set<String> allowed) {
      if (source.contains(webGatewayDenyAllSelectionMarker)) {
        return const <String>[webGatewayDenyAllSelectionMarker];
      }
      if (source.isEmpty) return const <String>[];
      return source.where(allowed.contains).toList(growable: false);
    }

    return normalizedValue.copyWith(
      allowedTemplateIds: keep(normalizedValue.allowedTemplateIds, templateIds),
      allowedSkillNames: keep(normalizedValue.allowedSkillNames, skills),
      allowedMcpServerNames: keep(
        normalizedValue.allowedMcpServerNames,
        mcpServers,
      ),
      allowedMemoryIds: keep(normalizedValue.allowedMemoryIds, memories),
      allowedBuiltinToolNames: keep(allowedToolNames, tools),
      allowedModelKeys: keep(normalizedValue.allowedModelKeys, models),
      allowedInstructionIds: keep(
        normalizedValue.allowedInstructionIds,
        instructions,
      ),
      allowedAgentIds: agents.isEmpty
          ? normalizedValue.allowedAgentIds
          : keep(normalizedValue.allowedAgentIds, agents),
    );
  }

  List<String> _withoutKnowledgeBaseBuiltinToolNames(List<String> source) {
    if (source.isEmpty || source.contains(webGatewayDenyAllSelectionMarker)) {
      return source;
    }
    final next = source
        .where((name) => !_isKnowledgeBaseBuiltinToolName(name))
        .toList(growable: false);
    return next.isEmpty
        ? const <String>[webGatewayDenyAllSelectionMarker]
        : next;
  }

  bool _isKnowledgeBaseBuiltinToolName(String name) {
    if (webGatewayIsKnowledgeBaseBuiltinToolName(name)) return true;
    return knowledgeBaseBuiltinToolNames.contains(name);
  }

  void _scheduleLogNotify() {
    _logNotifyDebouncer.scheduleIfIdle(notifyListeners);
  }

  /// 注入插件服务控制器到底层 Web 服务（延迟注入，避免循环依赖）。
  set pluginServiceController(PluginServiceController? controller) {
    _service.pluginServiceController = controller;
  }

  /// 释放通知器并有界关闭 HTTP 服务、订阅和自有媒体资源，可重复调用。
  @override
  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    final shutdown = () async {
      try {
        await super.shutdown();
      } finally {
        await (_resourceShutdownFuture ?? Future<void>.value());
      }
    }();
    _shutdownFuture = shutdown;
    return shutdown;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _logNotifyDebouncer.dispose();
    _saveSuccessPulse.dispose();
    _resourceShutdownFuture = Future.wait<bool>(<Future<bool>>[
      cancelStreamSubscriptionBounded<WebGatewayLogEntry>(
        _logSub,
        onError: (error, stack) =>
            silentLog('message_gateway', '取消日志订阅', error, stack),
      ),
      runAsyncCleanupBounded(
        _service.dispose,
        timeout: runtimeCleanupTimeout,
        onError: (error, stack) =>
            silentLog('message_gateway', '关闭消息网关服务', error, stack),
      ),
      runAsyncCleanupBounded(
        _dingtalkController.shutdown,
        timeout: runtimeCleanupTimeout,
        onError: (error, stack) =>
            silentLog('message_gateway', '关闭钉钉消息网关', error, stack),
      ),
    ]).then<void>((_) {});
    super.dispose();
  }

  String _hex(Color color) {
    final value = color.toARGB32();
    final rgb = value & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

List<String> _cleanStringValues(Iterable<Object?> values) {
  return stringListFromValue(values.toList(growable: false));
}
