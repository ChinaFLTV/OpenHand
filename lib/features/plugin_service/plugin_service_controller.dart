import 'dart:async';

import 'package:flutter/foundation.dart';

import 'model/plugin_info.dart';
import 'service/plugin_lifecycle_service.dart';
import 'service/plugin_scanner_service.dart';

/// 插件服务控制器。
///
/// 管理插件的扫描、安装、更新、卸载，并通知 UI 状态变化。
/// 处理插件间依赖关系，确保操作顺序正确。
class PluginServiceController extends ChangeNotifier {
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
  String? _errorMessage;
  final List<String> _operationLogs = [];
  final ValueNotifier<int> operationSuccessSignal = ValueNotifier<int>(0);

  List<PluginInfo> get plugins => _plugins;
  bool get isLoading => _isLoading;
  bool get isOperating => _isOperating;
  String? get errorMessage => _errorMessage;
  List<String> get operationLogs => List.unmodifiable(_operationLogs);

  PluginInfo? pluginById(String id) {
    for (final p in _plugins) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 初始化：扫描本机已安装的插件。
  Future<void> initialize() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _plugins = await _scanner.scanAll();
    } catch (e) {
      _errorMessage = '$e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 重新扫描所有插件状态。
  Future<void> rescan() async {
    _errorMessage = null;
    notifyListeners();
    try {
      _plugins = await _scanner.scanAll();
    } catch (e) {
      _errorMessage = '$e';
    }
    notifyListeners();
  }

  /// 安装指定插件。自动处理依赖关系。
  Future<bool> installPlugin(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) return false;
    // 检查依赖是否已安装
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
        'nodejs' => await _lifecycle.installNodeJs(
          onProgress: _addLog,
        ),
        'playwright' => await _lifecycle.installPlaywright(
          onProgress: _addLog,
        ),
        _ => const PluginOperationResult(
          success: false,
          message: '未知插件',
        ),
      };
      if (result.success) {
        operationSuccessSignal.value++;
        await rescan();
        return true;
      } else {
        _updatePluginStatus(pluginId, PluginStatus.error,
            errorMessage: result.message);
        _errorMessage = result.message;
        notifyListeners();
        return false;
      }
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
        _ => const PluginOperationResult(
          success: false,
          message: '未知插件',
        ),
      };
      if (result.success) {
        operationSuccessSignal.value++;
        await rescan();
        return true;
      } else {
        _updatePluginStatus(pluginId, PluginStatus.error,
            errorMessage: result.message);
        _errorMessage = result.message;
        notifyListeners();
        return false;
      }
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
    // 检查是否有已安装的插件依赖本插件
    for (final other in _plugins) {
      if (other.id == pluginId) continue;
      if (other.isInstalled && other.dependencies.contains(pluginId)) {
        _errorMessage = '${other.name} 依赖 ${plugin.name}，请先卸载 ${other.name}';
        notifyListeners();
        return false;
      }
    }
    _isOperating = true;
    _operationLogs.clear();
    _updatePluginStatus(pluginId, PluginStatus.uninstalling);
    notifyListeners();
    try {
      final playwrightInstalled = pluginById('playwright')?.isInstalled ?? false;
      final result = switch (pluginId) {
        'nodejs' => await _lifecycle.uninstallNodeJs(
          playwrightInstalled: playwrightInstalled,
          onProgress: _addLog,
        ),
        'playwright' => await _lifecycle.uninstallPlaywright(
          onProgress: _addLog,
        ),
        _ => const PluginOperationResult(
          success: false,
          message: '未知插件',
        ),
      };
      if (result.success) {
        operationSuccessSignal.value++;
        await rescan();
        return true;
      } else {
        _updatePluginStatus(pluginId, PluginStatus.error,
            errorMessage: result.message);
        _errorMessage = result.message;
        notifyListeners();
        return false;
      }
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
    operationSuccessSignal.dispose();
    super.dispose();
  }
}
