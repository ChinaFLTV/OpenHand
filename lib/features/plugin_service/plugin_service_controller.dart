import 'package:flutter/foundation.dart';

import '../../shared/core/managed_change_notifier.dart';
import 'model/plugin_info.dart';
import 'service/plugin_lifecycle_service.dart';
import 'service/plugin_scanner_service.dart';

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
  final List<String> _operationLogs = [];
  final ChangePulse _operationSuccessPulse = ChangePulse();

  List<PluginInfo> get plugins => _plugins;
  bool get isLoading => _isLoading;
  bool get isOperating => _isOperating;
  String? get checkingPluginId => _checkingPluginId;
  String? get errorMessage => _errorMessage;
  List<String> get operationLogs => List.unmodifiable(_operationLogs);
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
              dependents: pluginById('playwright')?.isInstalled == true
                  ? const ['playwright']
                  : const [],
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

  /// 安装指定插件。自动处理依赖关系。
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
    _isOperating = true;
    _operationLogs.clear();
    _updatePluginStatus(pluginId, PluginStatus.installing);
    notifyListeners();
    try {
      final result = switch (pluginId) {
        'nodejs' => await _lifecycle.installNodeJs(onProgress: _addLog),
        'playwright' => await _lifecycle.installPlaywright(onProgress: _addLog),
        'python' => await _lifecycle.installPython(onProgress: _addLog),
        'pip' => await _lifecycle.installPip(onProgress: _addLog),
        'java' => await _lifecycle.installJava(onProgress: _addLog),
        'frida' => await _lifecycle.installFrida(onProgress: _addLog),
        'mitmproxy' => await _lifecycle.installMitmproxy(onProgress: _addLog),
        'apktool' => await _lifecycle.installApktool(onProgress: _addLog),
        'jadx' => await _lifecycle.installJadx(onProgress: _addLog),
        'radare2' => await _lifecycle.installRadare2(onProgress: _addLog),
        'blutter' => await _lifecycle.installBlutter(onProgress: _addLog),
        'doldrums' => await _lifecycle.installDoldrums(onProgress: _addLog),
        'anything_analyzer' => await _lifecycle.installAnythingAnalyzer(
          onProgress: _addLog,
        ),
        'docker' => await _lifecycle.installDocker(onProgress: _addLog),
        'qdrant' => await _lifecycle.installQdrant(onProgress: _addLog),
        _ => const PluginOperationResult(success: false, message: '未知插件'),
      };
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

  /// 更新指定插件。如果有依赖需要连带更新，按顺序执行。
  Future<bool> updatePlugin(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null || !plugin.isInstalled) return false;
    _isOperating = true;
    _operationLogs.clear();
    _updatePluginStatus(pluginId, PluginStatus.updating);
    notifyListeners();
    try {
      final result = switch (pluginId) {
        'nodejs' => await _lifecycle.updateNodeJs(onProgress: _addLog),
        'playwright' => await _lifecycle.updatePlaywright(onProgress: _addLog),
        'python' => await _lifecycle.updatePython(onProgress: _addLog),
        'pip' => await _lifecycle.updatePip(onProgress: _addLog),
        'java' => await _lifecycle.updateJava(onProgress: _addLog),
        'frida' => await _lifecycle.updateFrida(onProgress: _addLog),
        'mitmproxy' => await _lifecycle.updateMitmproxy(onProgress: _addLog),
        'apktool' => await _lifecycle.updateApktool(onProgress: _addLog),
        'jadx' => await _lifecycle.updateJadx(onProgress: _addLog),
        'radare2' => await _lifecycle.updateRadare2(onProgress: _addLog),
        'blutter' => await _lifecycle.updateBlutter(onProgress: _addLog),
        'doldrums' => await _lifecycle.updateDoldrums(onProgress: _addLog),
        'anything_analyzer' => await _lifecycle.updateAnythingAnalyzer(
          onProgress: _addLog,
        ),
        'docker' => await _lifecycle.updateDocker(onProgress: _addLog),
        'qdrant' => await _lifecycle.updateQdrant(onProgress: _addLog),
        _ => const PluginOperationResult(success: false, message: '未知插件'),
      };
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

  /// 卸载指定插件。检查是否有其他插件依赖它。
  Future<bool> uninstallPlugin(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null || !plugin.isInstalled) return false;
    if (!plugin.supportsUninstall) {
      _errorMessage = '${plugin.name} 不支持卸载';
      notifyListeners();
      return false;
    }
    if (plugin.dependents.isNotEmpty) {
      for (final dependentId in plugin.dependents) {
        final dependent = pluginById(dependentId);
        if (dependent != null && dependent.isInstalled) {
          _errorMessage =
              '${dependent.name} 依赖 ${plugin.name}，请先卸载 ${dependent.name}';
          notifyListeners();
          return false;
        }
      }
    }
    _isOperating = true;
    _operationLogs.clear();
    _updatePluginStatus(pluginId, PluginStatus.uninstalling);
    notifyListeners();
    try {
      final playwrightInstalled =
          pluginById('playwright')?.isInstalled ?? false;
      final result = switch (pluginId) {
        'nodejs' => await _lifecycle.uninstallNodeJs(
          playwrightInstalled: playwrightInstalled,
          onProgress: _addLog,
        ),
        'playwright' => await _lifecycle.uninstallPlaywright(
          onProgress: _addLog,
        ),
        'python' => await _lifecycle.uninstallPython(onProgress: _addLog),
        'pip' => await _lifecycle.uninstallPip(onProgress: _addLog),
        'java' => await _lifecycle.uninstallJava(onProgress: _addLog),
        'frida' => await _lifecycle.uninstallFrida(onProgress: _addLog),
        'mitmproxy' => await _lifecycle.uninstallMitmproxy(onProgress: _addLog),
        'apktool' => await _lifecycle.uninstallApktool(onProgress: _addLog),
        'jadx' => await _lifecycle.uninstallJadx(onProgress: _addLog),
        'radare2' => await _lifecycle.uninstallRadare2(onProgress: _addLog),
        'blutter' => await _lifecycle.uninstallBlutter(onProgress: _addLog),
        'doldrums' => await _lifecycle.uninstallDoldrums(onProgress: _addLog),
        'anything_analyzer' => await _lifecycle.uninstallAnythingAnalyzer(
          onProgress: _addLog,
        ),
        'docker' => await _lifecycle.uninstallDocker(onProgress: _addLog),
        'qdrant' => await _lifecycle.uninstallQdrant(onProgress: _addLog),
        _ => const PluginOperationResult(success: false, message: '未知插件'),
      };
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

  void clearError() {
    _errorMessage = null;
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
          p.copyWith(status: status, errorMessage: errorMessage)
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
