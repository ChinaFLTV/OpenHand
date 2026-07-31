import 'package:flutter/foundation.dart';

import '../../shared/core/managed_change_notifier.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_log_buffer.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/version_compare.dart';
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
  final OpenHandSingleFlight<void> _refreshAllPluginsFlight =
      OpenHandSingleFlight<void>();
  final BoundedLogBuffer _operationLogs = BoundedLogBuffer();
  final ChangePulse _operationSuccessPulse = ChangePulse();

  List<PluginInfo> get plugins => _plugins;
  bool get isLoading => _isLoading;
  bool get isOperating => _isOperating;
  bool get isBusy => _isLoading || _isOperating || _checkingPluginId != null;
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
    if (_refreshAllPluginsFlight.isRunning) {
      return _refreshAllPluginsFlight.run(_refreshAllPluginsUncached);
    }
    if (_isOperating || _checkingPluginId != null) {
      return Future<void>.value();
    }
    return _refreshAllPlugins();
  }

  Future<void> _refreshAllPlugins() {
    return _refreshAllPluginsFlight.run(_refreshAllPluginsUncached);
  }

  Future<void> _refreshAllPluginsUncached() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _plugins = _mergeScannedPlugins(await _scanner.scanAll());
    } catch (e) {
      _errorMessage = '$e';
      if (_plugins.isEmpty) {
        _plugins = _mergeScannedPlugins(
          PluginScannerService.knownPluginPlaceholders(),
        );
      }
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
    for (final id in PluginCatalogIds.displayOrder) {
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
    if (plugin == null || isBusy) return null;
    _errorMessage = null;
    _checkingPluginId = pluginId;
    notifyListeners();
    try {
      final refreshed = await switch (pluginId) {
        PluginCatalogIds.nodejs => _scanner.scanNodeJs(),
        PluginCatalogIds.playwright => _scanner.scanPlaywright(),
        PluginCatalogIds.hermesAgent => _scanner.scanHermesAgent(),
        PluginCatalogIds.python => _scanner.scanPython(),
        PluginCatalogIds.pip => _scanner.scanPip(),
        PluginCatalogIds.java => _scanner.scanJava(),
        PluginCatalogIds.frida => _scanner.scanFrida(),
        PluginCatalogIds.mitmproxy => _scanner.scanMitmproxy(),
        PluginCatalogIds.apktool => _scanner.scanApktool(),
        PluginCatalogIds.jadx => _scanner.scanJadx(),
        PluginCatalogIds.radare2 => _scanner.scanRadare2(),
        PluginCatalogIds.blutter => _scanner.scanBlutter(),
        PluginCatalogIds.doldrums => _scanner.scanDoldrums(),
        PluginCatalogIds.anythingAnalyzer => _scanner.scanAnythingAnalyzer(),
        PluginCatalogIds.docker => _scanner.scanDocker(),
        PluginCatalogIds.qdrant => _scanner.scanQdrant(),
        _ => Future<PluginInfo?>.value(),
      };
      if (refreshed == null) return null;
      final merged = pluginId == PluginCatalogIds.nodejs
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
        PluginCatalogIds.nodejs => _lifecycle.installNodeJs(
          onProgress: _addLog,
        ),
        PluginCatalogIds.playwright => _lifecycle.installPlaywright(
          onProgress: _addLog,
        ),
        PluginCatalogIds.hermesAgent => _lifecycle.installHermesAgent(
          onProgress: _addLog,
        ),
        PluginCatalogIds.python => _lifecycle.installPython(
          onProgress: _addLog,
        ),
        PluginCatalogIds.pip => _lifecycle.installPip(onProgress: _addLog),
        PluginCatalogIds.java => _lifecycle.installJava(onProgress: _addLog),
        PluginCatalogIds.frida => _lifecycle.installFrida(onProgress: _addLog),
        PluginCatalogIds.mitmproxy => _lifecycle.installMitmproxy(
          onProgress: _addLog,
        ),
        PluginCatalogIds.apktool => _lifecycle.installApktool(
          onProgress: _addLog,
        ),
        PluginCatalogIds.jadx => _lifecycle.installJadx(onProgress: _addLog),
        PluginCatalogIds.radare2 => _lifecycle.installRadare2(
          onProgress: _addLog,
        ),
        PluginCatalogIds.blutter => _lifecycle.installBlutter(
          onProgress: _addLog,
        ),
        PluginCatalogIds.doldrums => _lifecycle.installDoldrums(
          onProgress: _addLog,
        ),
        PluginCatalogIds.anythingAnalyzer => _lifecycle.installAnythingAnalyzer(
          onProgress: _addLog,
        ),
        PluginCatalogIds.docker => _lifecycle.installDocker(
          onProgress: _addLog,
          shouldContinue: () => !isDisposed,
        ),
        PluginCatalogIds.qdrant => _lifecycle.installQdrant(
          onProgress: _addLog,
        ),
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
        PluginCatalogIds.nodejs => _lifecycle.updateNodeJs(onProgress: _addLog),
        PluginCatalogIds.playwright => _lifecycle.updatePlaywright(
          onProgress: _addLog,
        ),
        PluginCatalogIds.hermesAgent => _lifecycle.updateHermesAgent(
          onProgress: _addLog,
        ),
        PluginCatalogIds.python => _lifecycle.updatePython(onProgress: _addLog),
        PluginCatalogIds.pip => _lifecycle.updatePip(onProgress: _addLog),
        PluginCatalogIds.java => _lifecycle.updateJava(onProgress: _addLog),
        PluginCatalogIds.frida => _lifecycle.updateFrida(onProgress: _addLog),
        PluginCatalogIds.mitmproxy => _lifecycle.updateMitmproxy(
          onProgress: _addLog,
        ),
        PluginCatalogIds.apktool => _lifecycle.updateApktool(
          onProgress: _addLog,
        ),
        PluginCatalogIds.jadx => _lifecycle.updateJadx(onProgress: _addLog),
        PluginCatalogIds.radare2 => _lifecycle.updateRadare2(
          onProgress: _addLog,
        ),
        PluginCatalogIds.blutter => _lifecycle.updateBlutter(
          onProgress: _addLog,
        ),
        PluginCatalogIds.doldrums => _lifecycle.updateDoldrums(
          onProgress: _addLog,
        ),
        PluginCatalogIds.anythingAnalyzer => _lifecycle.updateAnythingAnalyzer(
          onProgress: _addLog,
        ),
        PluginCatalogIds.docker => _lifecycle.updateDocker(onProgress: _addLog),
        PluginCatalogIds.qdrant => _lifecycle.updateQdrant(onProgress: _addLog),
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
    final playwrightInstalled =
        pluginById(PluginCatalogIds.playwright)?.isInstalled ?? false;
    return _runPluginLifecycleOperation(
      pluginId: pluginId,
      transientStatus: PluginStatus.uninstalling,
      operation: () => switch (pluginId) {
        PluginCatalogIds.nodejs => _lifecycle.uninstallNodeJs(
          playwrightInstalled: playwrightInstalled,
          onProgress: _addLog,
        ),
        PluginCatalogIds.playwright => _lifecycle.uninstallPlaywright(
          onProgress: _addLog,
        ),
        PluginCatalogIds.hermesAgent => _lifecycle.uninstallHermesAgent(
          onProgress: _addLog,
        ),
        PluginCatalogIds.python => _lifecycle.uninstallPython(
          onProgress: _addLog,
        ),
        PluginCatalogIds.pip => _lifecycle.uninstallPip(onProgress: _addLog),
        PluginCatalogIds.java => _lifecycle.uninstallJava(onProgress: _addLog),
        PluginCatalogIds.frida => _lifecycle.uninstallFrida(
          onProgress: _addLog,
        ),
        PluginCatalogIds.mitmproxy => _lifecycle.uninstallMitmproxy(
          onProgress: _addLog,
        ),
        PluginCatalogIds.apktool => _lifecycle.uninstallApktool(
          onProgress: _addLog,
        ),
        PluginCatalogIds.jadx => _lifecycle.uninstallJadx(onProgress: _addLog),
        PluginCatalogIds.radare2 => _lifecycle.uninstallRadare2(
          onProgress: _addLog,
        ),
        PluginCatalogIds.blutter => _lifecycle.uninstallBlutter(
          onProgress: _addLog,
        ),
        PluginCatalogIds.doldrums => _lifecycle.uninstallDoldrums(
          onProgress: _addLog,
        ),
        PluginCatalogIds.anythingAnalyzer =>
          _lifecycle.uninstallAnythingAnalyzer(onProgress: _addLog),
        PluginCatalogIds.docker => _lifecycle.uninstallDocker(
          onProgress: _addLog,
        ),
        PluginCatalogIds.qdrant => _lifecycle.uninstallQdrant(
          onProgress: _addLog,
        ),
        _ => _unknownPluginOperation(),
      },
    );
  }

  Future<bool> _runPluginLifecycleOperation({
    required String pluginId,
    required PluginStatus transientStatus,
    required Future<PluginOperationResult> Function() operation,
  }) async {
    if (isBusy) return false;
    _isOperating = true;
    _errorMessage = null;
    _operationLogs.clear();
    _updatePluginStatus(pluginId, transientStatus);
    notifyListeners();
    try {
      final result = await operation();
      if (isDisposed) return false;
      if (result.success) {
        await _refreshAllPlugins();
        if (isDisposed) return false;
        final expectedVersion = result.newVersion?.trim();
        final verificationError = _pluginOperationVerificationError(
          pluginId: pluginId,
          transientStatus: transientStatus,
          expectedVersion: expectedVersion,
          refreshError: _errorMessage,
        );
        if (verificationError != null) {
          _setPluginOperationFailure(pluginId, verificationError);
          return false;
        }
        _operationSuccessPulse.emit();
        return true;
      }
      _setPluginOperationFailure(
        pluginId,
        result.message ??
            _pluginServiceText(
              zh: '插件操作失败',
              zhHant: '外掛操作失敗',
              en: 'Plugin operation failed.',
              fr: 'Échec de l’opération sur le plugin.',
              de: 'Der Plugin-Vorgang ist fehlgeschlagen.',
              ja: 'プラグイン操作に失敗しました。',
            ),
      );
      return false;
    } catch (e) {
      _setPluginOperationFailure(pluginId, '$e');
      return false;
    } finally {
      _isOperating = false;
      notifyListeners();
    }
  }

  String? _pluginOperationVerificationError({
    required String pluginId,
    required PluginStatus transientStatus,
    required String? expectedVersion,
    required String? refreshError,
  }) {
    final plugin = pluginById(pluginId);
    final name = plugin?.name ?? pluginId;
    if (refreshError != null) {
      return _pluginServiceText(
        zh: '操作已完成，但无法重新扫描 $name 状态：$refreshError',
        zhHant: '操作已完成，但無法重新掃描 $name 狀態：$refreshError',
        en: 'The operation completed, but $name could not be rescanned: $refreshError',
        fr: 'L’opération est terminée, mais l’état de $name n’a pas pu être vérifié : $refreshError',
        de: 'Der Vorgang wurde abgeschlossen, aber der Status von $name konnte nicht erneut geprüft werden: $refreshError',
        ja: '操作は完了しましたが、$name の状態を再確認できませんでした：$refreshError',
      );
    }
    if (transientStatus == PluginStatus.uninstalling) {
      if (plugin == null || plugin.status == PluginStatus.notInstalled) {
        return null;
      }
      return _pluginServiceText(
        zh: '$name 卸载后仍可检测到，结果未通过校验',
        zhHant: '$name 解除安裝後仍可偵測到，結果未通過驗證',
        en: '$name is still detected after uninstall and failed verification.',
        fr: '$name est toujours détecté après la désinstallation ; la vérification a échoué.',
        de: '$name wird nach der Deinstallation weiterhin erkannt; die Überprüfung ist fehlgeschlagen.',
        ja: '$name はアンインストール後も検出され、確認に失敗しました。',
      );
    }
    if (plugin?.status != PluginStatus.installed) {
      return _pluginServiceText(
        zh: '$name 操作后未处于可用状态，结果未通过校验',
        zhHant: '$name 操作後未處於可用狀態，結果未通過驗證',
        en: '$name is not available after the operation and failed verification.',
        fr: '$name n’est pas disponible après l’opération ; la vérification a échoué.',
        de: '$name ist nach dem Vorgang nicht verfügbar; die Überprüfung ist fehlgeschlagen.',
        ja: '$name は操作後に利用可能な状態ではなく、確認に失敗しました。',
      );
    }
    if (expectedVersion == null || expectedVersion.isEmpty) return null;
    final actualVersion = plugin?.installedVersion?.trim();
    if (actualVersion != null &&
        actualVersion.isNotEmpty &&
        compareSemanticVersions(actualVersion, expectedVersion) >= 0) {
      return null;
    }
    final actualLabel = actualVersion?.isNotEmpty == true
        ? actualVersion!
        : _pluginServiceText(
            zh: '未检测到',
            zhHant: '未偵測到',
            en: 'not detected',
            fr: 'non détecté',
            de: 'nicht erkannt',
            ja: '未検出',
          );
    return _pluginServiceText(
      zh: '操作后版本校验失败：预期 $expectedVersion，实际 $actualLabel',
      zhHant: '操作後版本驗證失敗：預期 $expectedVersion，實際 $actualLabel',
      en: 'Post-operation verification failed: expected $expectedVersion, got $actualLabel.',
      fr: 'Échec de la vérification après l’opération : $expectedVersion attendu, $actualLabel obtenu.',
      de: 'Überprüfung nach dem Vorgang fehlgeschlagen: erwartet $expectedVersion, erhalten $actualLabel.',
      ja: '操作後のバージョン確認に失敗しました：期待値 $expectedVersion、実際 $actualLabel。',
    );
  }

  void _setPluginOperationFailure(String pluginId, String message) {
    _updatePluginStatus(pluginId, PluginStatus.error, errorMessage: message);
    _errorMessage = message;
    notifyListeners();
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

  PluginStatus _restoredStatusAfterFailedOperation(PluginInfo plugin) {
    final hasInstalledSignal =
        plugin.installedVersion?.trim().isNotEmpty == true ||
        plugin.installPath?.trim().isNotEmpty == true;
    return hasInstalledSignal
        ? PluginStatus.installed
        : PluginStatus.notInstalled;
  }

  void _addLog(String line) {
    if (isDisposed) return;
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
