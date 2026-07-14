import 'package:flutter/foundation.dart';

import '../../shared/core/managed_change_notifier.dart';
import '../../shared/util/bounded_log_buffer.dart';
import '../../shared/util/localized_text.dart';
import 'model/plugin_info.dart';
import 'service/plugin_lifecycle_service.dart';
import 'service/plugin_scanner_service.dart';

String _pluginServiceText({
  required String zh,
  required String en,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  return openHandLocalizedTextForLocale(
    PlatformDispatcher.instance.locale,
    zh: zh,
    zhHant: zhHant,
    en: en,
    fr: fr,
    de: de,
    ja: ja,
  );
}

/// 插件服务控制器。
///
/// 管理插件的扫描、安装、更新、卸载，并通知 UI 状态变化。
/// 处理插件间依赖关系，确保操作顺序正确。
class PluginServiceController extends ManagedChangeNotifier {
  PluginServiceController({
    PluginScannerService? scanner,
    PluginLifecycleService? lifecycle,
  }) : _scanner = scanner ?? PluginScannerService(),
       _lifecycle = lifecycle ?? PluginLifecycleService();

  final PluginScannerService _scanner;
  final PluginLifecycleService _lifecycle;

  List<PluginInfo> _plugins = [];
  bool _isLoading = true;
  bool _isOperating = false;
  String? _checkingPluginId;
  String? _errorMessage;
  Future<void>? _refreshAllPluginsFuture;
  final BoundedLogBuffer _operationLogs = BoundedLogBuffer();
  final ChangePulse _operationSuccessPulse = ChangePulse();

  List<PluginInfo> get plugins => _plugins;
  bool get isLoading => _isLoading;
  bool get isOperating => _isOperating;
  String? get checkingPluginId => _checkingPluginId;
  String? get errorMessage => _errorMessage;
  List<String> get operationLogs => _operationLogs.snapshot();
  int get operationLogRevision => _operationLogs.revision;
  ValueListenable<int> get operationSuccessSignal =>
      _operationSuccessPulse.listenable;

  PluginInfo? pluginById(String id) {
    for (final p in _plugins) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 初始化：扫描本机已安装的插件。
  Future<void> initialize() {
    return _refreshAllPlugins();
  }

  /// 重新扫描所有插件状态。
  Future<void> rescan() {
    return _refreshAllPlugins();
  }

  Future<void> _refreshAllPlugins() {
    final active = _refreshAllPluginsFuture;
    if (active != null) return active;
    late final Future<void> refresh;
    refresh = _refreshAllPluginsUncached().whenComplete(() {
      if (identical(_refreshAllPluginsFuture, refresh)) {
        _refreshAllPluginsFuture = null;
      }
    });
    _refreshAllPluginsFuture = refresh;
    return refresh;
  }

  Future<void> _refreshAllPluginsUncached() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _plugins = _mergeScannedPlugins(await _scanner.scanAll());
    } catch (e) {
      _errorMessage = '$e';
      _plugins = _mergeScannedPlugins(
        PluginScannerService.knownPluginPlaceholders(),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<PluginInfo> _mergeScannedPlugins(List<PluginInfo> scanned) {
    final previousById = <String, PluginInfo>{
      for (final plugin in _plugins) plugin.id: plugin,
    };
    final byId = <String, PluginInfo>{
      for (final plugin in PluginScannerService.knownPluginPlaceholders())
        plugin.id: plugin,
      for (final plugin in scanned) plugin.id: plugin,
    };
    final result = <PluginInfo>[];
    final seen = <String>{};
    // 插件页展示顺序按插件被纳入 OpenHand 的时间顺序固定；新增插件只能
    // 追加到列表末尾，不能因为依赖关系或功能分组插入到中间，避免用户
    // 看到既有插件位置跳动。
    for (final id in const <String>[
      'nodejs',
      'playwright',
      'python',
      'pip',
      'java',
      'frida',
      'mitmproxy',
      'apktool',
      'jadx',
      'radare2',
      'blutter',
      'doldrums',
      'anything_analyzer',
      'docker',
      'qdrant',
      PluginCatalogIds.hermesAgent,
    ]) {
      final plugin = byId[id];
      if (plugin == null) continue;
      seen.add(id);
      result.add(_restoreRuntimeState(plugin, previousById[id]));
    }
    for (final plugin in byId.values) {
      if (seen.contains(plugin.id)) continue;
      result.add(_restoreRuntimeState(plugin, previousById[plugin.id]));
    }
    return List<PluginInfo>.unmodifiable(result);
  }

  PluginInfo _restoreRuntimeState(PluginInfo next, PluginInfo? previous) {
    if (previous == null || !next.isInstalled) {
      return next.isInstalled ? next : next.copyWith(enabled: true);
    }
    return next.copyWith(enabled: previous.enabled);
  }

  /// 检查单个插件的最新状态与可更新版本。
  Future<PluginInfo?> checkPluginUpdate(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) return null;
    _errorMessage = null;
    _checkingPluginId = pluginId;
    notifyListeners();
    try {
      final refreshed = await switch (pluginId) {
        'nodejs' => _scanner.scanNodeJs(),
        'playwright' => _scanner.scanPlaywright(),
        PluginCatalogIds.hermesAgent => _scanner.scanHermesAgent(),
        'python' => _scanner.scanPython(),
        'pip' => _scanner.scanPip(),
        'java' => _scanner.scanJava(),
        'frida' => _scanner.scanFrida(),
        'mitmproxy' => _scanner.scanMitmproxy(),
        'apktool' => _scanner.scanApktool(),
        'jadx' => _scanner.scanJadx(),
        'radare2' => _scanner.scanRadare2(),
        'blutter' => _scanner.scanBlutter(),
        'doldrums' => _scanner.scanDoldrums(),
        'anything_analyzer' => _scanner.scanAnythingAnalyzer(),
        'docker' => _scanner.scanDocker(),
        'qdrant' => _scanner.scanQdrant(),
        _ => Future<PluginInfo?>.value(),
      };
      if (refreshed == null) return null;
      final merged = pluginId == 'nodejs'
          ? refreshed.copyWith(
              dependents: <String>[
                if (pluginById(PluginCatalogIds.playwright)?.isInstalled ==
                    true)
                  PluginCatalogIds.playwright,
                if (pluginById(PluginCatalogIds.hermesAgent)?.isInstalled ==
                    true)
                  PluginCatalogIds.hermesAgent,
              ],
            )
          : refreshed;
      _plugins = [
        for (final p in _plugins)
          if (p.id == pluginId) merged.copyWith(enabled: p.enabled) else p,
      ];
      notifyListeners();
      return merged;
    } catch (e) {
      _errorMessage = '$e';
      notifyListeners();
      return null;
    } finally {
      _checkingPluginId = null;
      notifyListeners();
    }
  }

  /// 切换插件启用/禁用状态。
  void toggleEnabled(String pluginId, {required bool enabled}) {
    _plugins = [
      for (final p in _plugins)
        if (p.id == pluginId) p.copyWith(enabled: enabled) else p,
    ];
    if (!enabled) {
      _plugins = [
        for (final p in _plugins)
          if (p.dependencies.contains(pluginId) && p.isInstalled)
            p.copyWith(enabled: false)
          else
            p,
      ];
    }
    notifyListeners();
  }

  /// 安装指定插件。安装前校验依赖关系。
  Future<bool> installPlugin(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) return false;
    for (final depId in plugin.dependencies) {
      final dep = pluginById(depId);
      if (dep == null || !dep.isInstalled) {
        _errorMessage = '需要先安装 ${dep?.name ?? depId}';
        notifyListeners();
        return false;
      }
    }
    return _runPluginLifecycleOperation(
      pluginId: pluginId,
      transientStatus: PluginStatus.installing,
      operation: () => switch (pluginId) {
        'nodejs' => _lifecycle.installNodeJs(onProgress: _addLog),
        'playwright' => _lifecycle.installPlaywright(onProgress: _addLog),
        PluginCatalogIds.hermesAgent => _lifecycle.installHermesAgent(
          onProgress: _addLog,
        ),
        'python' => _lifecycle.installPython(onProgress: _addLog),
        'pip' => _lifecycle.installPip(onProgress: _addLog),
        'java' => _lifecycle.installJava(onProgress: _addLog),
        'frida' => _lifecycle.installFrida(onProgress: _addLog),
        'mitmproxy' => _lifecycle.installMitmproxy(onProgress: _addLog),
        'apktool' => _lifecycle.installApktool(onProgress: _addLog),
        'jadx' => _lifecycle.installJadx(onProgress: _addLog),
        'radare2' => _lifecycle.installRadare2(onProgress: _addLog),
        'blutter' => _lifecycle.installBlutter(onProgress: _addLog),
        'doldrums' => _lifecycle.installDoldrums(onProgress: _addLog),
        'anything_analyzer' => _lifecycle.installAnythingAnalyzer(
          onProgress: _addLog,
        ),
        'docker' => _lifecycle.installDocker(onProgress: _addLog),
        'qdrant' => _lifecycle.installQdrant(onProgress: _addLog),
        _ => _unknownPluginOperation(),
      },
    );
  }

  /// 更新指定的已安装插件。
  Future<bool> updatePlugin(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null || !plugin.isInstalled) return false;
    return _runPluginLifecycleOperation(
      pluginId: pluginId,
      transientStatus: PluginStatus.updating,
      operation: () => switch (pluginId) {
        'nodejs' => _lifecycle.updateNodeJs(onProgress: _addLog),
        'playwright' => _lifecycle.updatePlaywright(onProgress: _addLog),
        PluginCatalogIds.hermesAgent => _lifecycle.updateHermesAgent(
          onProgress: _addLog,
        ),
        'python' => _lifecycle.updatePython(onProgress: _addLog),
        'pip' => _lifecycle.updatePip(onProgress: _addLog),
        'java' => _lifecycle.updateJava(onProgress: _addLog),
        'frida' => _lifecycle.updateFrida(onProgress: _addLog),
        'mitmproxy' => _lifecycle.updateMitmproxy(onProgress: _addLog),
        'apktool' => _lifecycle.updateApktool(onProgress: _addLog),
        'jadx' => _lifecycle.updateJadx(onProgress: _addLog),
        'radare2' => _lifecycle.updateRadare2(onProgress: _addLog),
        'blutter' => _lifecycle.updateBlutter(onProgress: _addLog),
        'doldrums' => _lifecycle.updateDoldrums(onProgress: _addLog),
        'anything_analyzer' => _lifecycle.updateAnythingAnalyzer(
          onProgress: _addLog,
        ),
        'docker' => _lifecycle.updateDocker(onProgress: _addLog),
        'qdrant' => _lifecycle.updateQdrant(onProgress: _addLog),
        _ => _unknownPluginOperation(),
      },
    );
  }

  /// 卸载指定插件。检查是否有其他插件依赖它。
  Future<bool> uninstallPlugin(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null || !plugin.isInstalled) return false;
    if (!plugin.supportsUninstall) {
      _errorMessage = _pluginServiceText(
        zh: '${plugin.name} 不支持卸载',
        zhHant: '${plugin.name} 不支援卸載',
        en: '${plugin.name} does not support uninstall.',
        fr: '${plugin.name} ne prend pas en charge la désinstallation.',
        de: '${plugin.name} unterstützt keine Deinstallation.',
        ja: '${plugin.name} はアンインストールに対応していません。',
      );
      notifyListeners();
      return false;
    }
    if (plugin.dependents.isNotEmpty) {
      for (final dependentId in plugin.dependents) {
        final dependent = pluginById(dependentId);
        if (dependent != null && dependent.isInstalled) {
          _errorMessage = _pluginServiceText(
            zh: '${dependent.name} 依赖 ${plugin.name}，请先卸载 ${dependent.name}',
            zhHant:
                '${dependent.name} 依賴 ${plugin.name}，請先卸載 ${dependent.name}',
            en: '${dependent.name} depends on ${plugin.name}. Uninstall ${dependent.name} first.',
            fr: '${dependent.name} dépend de ${plugin.name}. Désinstallez d’abord ${dependent.name}.',
            de: '${dependent.name} hängt von ${plugin.name} ab. Deinstalliere zuerst ${dependent.name}.',
            ja: '${dependent.name} は ${plugin.name} に依存しています。先に ${dependent.name} をアンインストールしてください。',
          );
          notifyListeners();
          return false;
        }
      }
    }
    final playwrightInstalled = pluginById('playwright')?.isInstalled ?? false;
    return _runPluginLifecycleOperation(
      pluginId: pluginId,
      transientStatus: PluginStatus.uninstalling,
      operation: () => switch (pluginId) {
        'nodejs' => _lifecycle.uninstallNodeJs(
          playwrightInstalled: playwrightInstalled,
          onProgress: _addLog,
        ),
        'playwright' => _lifecycle.uninstallPlaywright(onProgress: _addLog),
        PluginCatalogIds.hermesAgent => _lifecycle.uninstallHermesAgent(
          onProgress: _addLog,
        ),
        'python' => _lifecycle.uninstallPython(onProgress: _addLog),
        'pip' => _lifecycle.uninstallPip(onProgress: _addLog),
        'java' => _lifecycle.uninstallJava(onProgress: _addLog),
        'frida' => _lifecycle.uninstallFrida(onProgress: _addLog),
        'mitmproxy' => _lifecycle.uninstallMitmproxy(onProgress: _addLog),
        'apktool' => _lifecycle.uninstallApktool(onProgress: _addLog),
        'jadx' => _lifecycle.uninstallJadx(onProgress: _addLog),
        'radare2' => _lifecycle.uninstallRadare2(onProgress: _addLog),
        'blutter' => _lifecycle.uninstallBlutter(onProgress: _addLog),
        'doldrums' => _lifecycle.uninstallDoldrums(onProgress: _addLog),
        'anything_analyzer' => _lifecycle.uninstallAnythingAnalyzer(
          onProgress: _addLog,
        ),
        'docker' => _lifecycle.uninstallDocker(onProgress: _addLog),
        'qdrant' => _lifecycle.uninstallQdrant(onProgress: _addLog),
        _ => _unknownPluginOperation(),
      },
    );
  }

  Future<bool> _runPluginLifecycleOperation({
    required String pluginId,
    required PluginStatus transientStatus,
    required Future<PluginOperationResult> Function() operation,
  }) async {
    _isOperating = true;
    _operationLogs.clear();
    _updatePluginStatus(pluginId, transientStatus);
    notifyListeners();
    try {
      final result = await operation();
      if (result.success) {
        _operationSuccessPulse.emit();
        await rescan();
        return true;
      }
      _updatePluginStatus(
        pluginId,
        PluginStatus.error,
        errorMessage: result.message,
      );
      _errorMessage = result.message;
      notifyListeners();
      return false;
    } catch (e) {
      _updatePluginStatus(pluginId, PluginStatus.error, errorMessage: '$e');
      _errorMessage = '$e';
      notifyListeners();
      return false;
    } finally {
      _isOperating = false;
      notifyListeners();
    }
  }

  Future<PluginOperationResult> _unknownPluginOperation() {
    return Future<PluginOperationResult>.value(
      PluginOperationResult(success: false, message: _unknownPluginMessage()),
    );
  }

  String _unknownPluginMessage() {
    return _pluginServiceText(
      zh: '未知插件',
      zhHant: '未知外掛',
      en: 'Unknown plugin',
      fr: 'Plugin inconnu',
      de: 'Unbekanntes Plugin',
      ja: '不明なプラグイン',
    );
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearPluginError(String pluginId) {
    final plugin = pluginById(pluginId);
    if (plugin == null || plugin.errorMessage == null) return;
    final wasOperationFailure =
        _errorMessage != null && _errorMessage == plugin.errorMessage;
    _plugins = [
      for (final p in _plugins)
        if (p.id == pluginId)
          p.copyWith(
            status: wasOperationFailure
                ? _restoredStatusAfterFailedOperation(p)
                : p.status,
            clearErrorMessage: true,
          )
        else
          p,
    ];
    if (wasOperationFailure) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  /// 强制取消当前操作（用户关闭进度弹窗时调用）。
  /// 重置操作状态并触发重新扫描以恢复真实状态。
  void forceCancel() {
    _isOperating = false;
    _plugins = [
      for (final p in _plugins)
        if (p.isBusy) p.copyWith(status: PluginStatus.installed) else p,
    ];
    notifyListeners();
    rescan();
  }

  PluginStatus _restoredStatusAfterFailedOperation(PluginInfo plugin) {
    final hasInstalledSignal =
        plugin.installedVersion?.trim().isNotEmpty == true ||
        plugin.installPath?.trim().isNotEmpty == true;
    return hasInstalledSignal
        ? PluginStatus.installed
        : PluginStatus.notInstalled;
  }

  void _addLog(String line) {
    _operationLogs.add(line);
    notifyListeners();
  }

  void _updatePluginStatus(
    String pluginId,
    PluginStatus status, {
    String? errorMessage,
  }) {
    _plugins = [
      for (final p in _plugins)
        if (p.id == pluginId)
          p.copyWith(
            status: status,
            errorMessage: errorMessage,
            clearErrorMessage: errorMessage == null,
          )
        else
          p,
    ];
  }

  @override
  void dispose() {
    _operationSuccessPulse.dispose();
    super.dispose();
  }
}
