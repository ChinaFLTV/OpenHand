import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/platform_shell.dart';
import '../../model/ai_command_rule.dart';
import '../../model/ai_sandbox_settings.dart';
import 'ai_e2b_sandbox_service.dart';
import 'ai_sandbox_proxy_service.dart';

class AiSandboxEnvironmentStatus {
  const AiSandboxEnvironmentStatus({
    required this.platform,
    required this.supported,
    required this.available,
    required this.backend,
    required this.missingDependencies,
    required this.warnings,
    this.resourceInstalled = false,
    this.resourceManaged = false,
    this.resourceUpdateAvailable = false,
    this.resourceVersion = '',
    this.reason = '',
  });

  final String platform;
  final bool supported;
  final bool available;
  final String backend;
  final List<String> missingDependencies;
  final List<String> warnings;
  final bool resourceInstalled;
  final bool resourceManaged;
  final bool resourceUpdateAvailable;
  final String resourceVersion;
  final String reason;

  String get unavailableReason {
    if (available) return '';
    if (reason.isNotEmpty) return reason;
    if (!supported) {
      return 'Sandbox is not supported on $platform.';
    }
    if (missingDependencies.isNotEmpty) {
      return 'Missing sandbox dependency: ${missingDependencies.join(', ')}.';
    }
    return 'Sandbox is unavailable.';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'platform': platform,
      'supported': supported,
      'available': available,
      'backend': backend,
      'missing_dependencies': missingDependencies,
      'warnings': warnings,
      'resource_installed': resourceInstalled,
      'resource_managed': resourceManaged,
      'resource_update_available': resourceUpdateAvailable,
      if (resourceVersion.isNotEmpty) 'resource_version': resourceVersion,
      if (reason.isNotEmpty) 'reason': reason,
    };
  }
}

const Duration _sandboxPathProbeIdleTimeout = Duration(milliseconds: 500);
const Duration _sandboxPathProbeTotalTimeout = Duration(seconds: 5);

class AiSandboxActionResult {
  const AiSandboxActionResult({
    required this.success,
    required this.message,
    this.command = '',
  });

  final bool success;
  final String message;
  final String command;
}

enum AiSandboxResourceAction { install, update, uninstall }

typedef AiSandboxActionProgress =
    void Function(double progress, String message);

class _LinuxSandboxPackageManager {
  const _LinuxSandboxPackageManager({
    required this.executable,
    required this.installArguments,
    required this.updateArguments,
    required this.uninstallArguments,
  });

  final String executable;
  final List<String> installArguments;
  final List<String> updateArguments;
  final List<String> uninstallArguments;

  List<String> argumentsFor(AiSandboxResourceAction action) => switch (action) {
    AiSandboxResourceAction.install => installArguments,
    AiSandboxResourceAction.update => updateArguments,
    AiSandboxResourceAction.uninstall => uninstallArguments,
  };
}

class AiSandboxLaunchSpec {
  const AiSandboxLaunchSpec({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.applied,
    required this.blocked,
    required this.metadata,
    this.proxyLease,
    this.reason = '',
    this.remote = false,
  });

  factory AiSandboxLaunchSpec.unsandboxed({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String> environment = const <String, String>{},
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiSandboxLaunchSpec(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      applied: false,
      blocked: false,
      metadata: metadata,
    );
  }

  factory AiSandboxLaunchSpec.blocked({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required String reason,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiSandboxLaunchSpec(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: const <String, String>{},
      applied: false,
      blocked: true,
      reason: reason,
      metadata: <String, Object?>{
        ...metadata,
        'sandbox_blocked': true,
        'sandbox_unavailable_reason': reason,
      },
    );
  }

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final bool applied;
  final bool blocked;
  final String reason;
  final bool remote;
  final Map<String, Object?> metadata;
  final AiSandboxProxyLease? proxyLease;
}

class AiSandboxService {
  AiSandboxService({AiSandboxSettings? settings})
    : _settings = settings ?? AiSandboxSettings.defaults() {
    _e2bService = AiE2bSandboxService(settings: _settings);
  }

  static const String _linuxDomainFilterUnavailableReason =
      'Linux bubblewrap cannot strictly enforce sandbox domain allow/deny rules yet because direct network access cannot be restricted to the OpenHand local proxy without an additional network bridge.';
  static const String _linuxDomainFilterBestEffortWarning =
      'Linux sandbox domain rules are best-effort here: OpenHand injects proxy environment variables, but bubblewrap does not block direct network bypass in this mode.';
  static const String _unsafeWritableRootReason =
      'Sandbox refused to grant writable access to an unsafe working directory root.';

  AiSandboxSettings _settings;
  late final AiE2bSandboxService _e2bService;
  final AiSandboxProxyService _proxyService = AiSandboxProxyService();
  AiSandboxEnvironmentStatus? _cachedStatus;

  AiSandboxSettings get settings => _settings;

  /// 换设置必须让环境探测缓存失效：[detectEnvironment] 缓存的 warnings 依赖
  /// filesystemRules 的匹配模式与域名规则，沿用旧缓存会让 UI 长期显示与当前
  /// 设置不符的告警。此前只有设置面板记得手动 refresh，运行时下发那条路径没有。
  set settings(AiSandboxSettings value) {
    if (_settings == value) return;
    _settings = value;
    _e2bService.settings = value;
    _cachedStatus = null;
  }

  Future<AiSandboxEnvironmentStatus> detectEnvironment({
    bool refresh = false,
  }) async {
    if (!refresh && _cachedStatus != null) return _cachedStatus!;
    if (settings.provider == AiSandboxProvider.e2b) {
      final issue = _e2bService.configurationIssue;
      if (issue.isNotEmpty) {
        return _cachedStatus = AiSandboxEnvironmentStatus(
          platform: 'cloud',
          supported: true,
          available: false,
          backend: 'e2b',
          missingDependencies: const <String>[],
          warnings: const <String>[],
          reason: issue,
        );
      }
      try {
        await _e2bService.probe();
        return _cachedStatus = const AiSandboxEnvironmentStatus(
          platform: 'cloud',
          supported: true,
          available: true,
          backend: 'e2b',
          missingDependencies: <String>[],
          warnings: <String>[],
        );
      } catch (error) {
        return _cachedStatus = AiSandboxEnvironmentStatus(
          platform: 'cloud',
          supported: true,
          available: false,
          backend: 'e2b',
          missingDependencies: const <String>[],
          warnings: const <String>[],
          reason: 'E2B 服务不可用：$error',
        );
      }
    }
    final platform = Platform.operatingSystem;
    final warnings = <String>[];
    final missing = <String>[];
    String backend = '';
    var supported = false;
    var resourceInstalled = false;
    var resourceManaged = false;
    var resourceUpdateAvailable = false;
    var resourceVersion = '';

    if (Platform.isMacOS) {
      supported = true;
      backend = 'sandbox-exec';
      resourceInstalled = await _commandExists('sandbox-exec');
      if (!resourceInstalled) missing.add('sandbox-exec');
    } else if (Platform.isLinux) {
      supported = true;
      backend = 'bubblewrap';
      resourceInstalled = await _commandExists('bwrap');
      if (!resourceInstalled) missing.add('bwrap');
      if (!await _commandExists('sh')) missing.add('sh');
      final packageManager = await _resolveLinuxPackageManager();
      resourceManaged = packageManager != null;
      if (resourceInstalled) {
        resourceVersion = await _readBubblewrapVersion();
        resourceUpdateAvailable =
            packageManager != null &&
            await _hasBubblewrapUpdate(packageManager);
      }
      if (settings.filesystemRules.any(
        (rule) => rule.matchMode == AiCommandMatchMode.regex,
      )) {
        warnings.add(
          'Linux bubblewrap cannot enforce regex filesystem paths directly; use simple path patterns for OS-level enforcement.',
        );
      }
    } else {
      supported = false;
      backend = 'unsupported';
    }

    if (settings.hasDomainRules) {
      if (Platform.isLinux) {
        warnings.add(_linuxDomainFilterUnavailableReason);
        if (!settings.failIfUnavailable) {
          warnings.add(_linuxDomainFilterBestEffortWarning);
        }
      } else {
        warnings.add(
          'Domain allow/deny lists are enforced through a per-command local proxy. macOS blocks direct network access outside that proxy.',
        );
      }
    }

    final status = AiSandboxEnvironmentStatus(
      platform: platform,
      supported: supported,
      available: supported && missing.isEmpty,
      backend: backend,
      missingDependencies: List<String>.unmodifiable(missing),
      warnings: List<String>.unmodifiable(warnings),
      resourceInstalled: resourceInstalled,
      resourceManaged: resourceManaged,
      resourceUpdateAvailable: resourceUpdateAvailable,
      resourceVersion: resourceVersion,
    );
    _cachedStatus = status;
    return status;
  }

  Future<AiSandboxActionResult> installEnvironment() async {
    return performEnvironmentAction(AiSandboxResourceAction.install);
  }

  Future<AiSandboxActionResult> updateEnvironment() async {
    return performEnvironmentAction(AiSandboxResourceAction.update);
  }

  Future<AiSandboxActionResult> uninstallEnvironment() async {
    return performEnvironmentAction(AiSandboxResourceAction.uninstall);
  }

  Future<AiSandboxActionResult> performEnvironmentAction(
    AiSandboxResourceAction action, {
    AiSandboxActionProgress? onProgress,
    Future<void>? cancelSignal,
  }) async {
    if (Platform.isMacOS) {
      final status = await detectEnvironment(refresh: true);
      return AiSandboxActionResult(
        success:
            action != AiSandboxResourceAction.uninstall && status.available,
        message: status.available
            ? 'macOS 沙盒由系统提供，无需单独维护。'
            : 'macOS 沙盒由系统提供，OpenHand 无法单独安装或移除。',
      );
    }
    if (!Platform.isLinux) {
      return const AiSandboxActionResult(
        success: false,
        message: '当前平台不支持维护本地沙盒资源。',
      );
    }
    final manager = await _resolveLinuxPackageManager();
    if (manager == null) {
      return const AiSandboxActionResult(
        success: false,
        message: '未找到受支持的系统包管理器。',
      );
    }
    onProgress?.call(0.08, '正在检查系统权限');
    final userId = await runTrackedProcessOrFailed(
      'id',
      const <String>['-u'],
      timeout: const Duration(seconds: 3),
      tag: 'ai_sandbox.package_user',
    );
    final isRoot = userId.exitCode == 0 && '${userId.stdout}'.trim() == '0';
    final canElevate = isRoot || await _commandExists('pkexec');
    if (!canElevate) {
      return const AiSandboxActionResult(
        success: false,
        message: '缺少图形化提权组件 pkexec，无法安全执行系统资源操作。',
      );
    }

    onProgress?.call(0.16, '正在启动系统资源任务');
    var latestMessage = '正在等待系统包管理器';
    void handleLine(String line) {
      final normalized = line.trim();
      if (normalized.isEmpty) return;
      latestMessage = normalized;
      onProgress?.call(0.72, normalized);
    }

    final arguments = manager.argumentsFor(action);
    final result = await runTrackedProcessWithLineLogging(
      isRoot ? manager.executable : 'pkexec',
      isRoot ? arguments : <String>[manager.executable, ...arguments],
      timeout: const Duration(minutes: 15),
      processStartTimeout: const Duration(seconds: 20),
      cancelSignal: cancelSignal,
      tag: 'ai_sandbox.package_action',
      onStdoutLine: handleLine,
      onStderrLine: handleLine,
      maxCapturedLinesPerStream: 40,
      maxCapturedCharactersPerStream: 16000,
      trimStdoutLines: true,
    );
    _cachedStatus = null;
    if (result.cancelled) {
      return const AiSandboxActionResult(success: false, message: '资源任务已取消。');
    }
    if (result.timedOut) {
      return const AiSandboxActionResult(
        success: false,
        message: '资源任务执行超时，相关进程已终止。',
      );
    }
    if (result.exitCode != 0) {
      return AiSandboxActionResult(
        success: false,
        message: latestMessage.isEmpty ? '系统包管理器执行失败。' : latestMessage,
      );
    }
    onProgress?.call(1, '系统资源状态已更新');
    return AiSandboxActionResult(
      success: true,
      message: switch (action) {
        AiSandboxResourceAction.install => '本地沙盒资源已安装。',
        AiSandboxResourceAction.update => '本地沙盒资源已更新。',
        AiSandboxResourceAction.uninstall => '本地沙盒资源已卸载。',
      },
    );
  }

  Future<AiSandboxLaunchSpec> prepareShellCommand({
    required String toolName,
    required String command,
    required String shellExecutable,
    required List<String> shellArguments,
    required String workingDirectory,
    bool dangerouslyDisableSandbox = false,
  }) async {
    final normalizedWorkingDirectory = _normalizeWorkingDirectory(
      workingDirectory,
    );
    // 用户配置的系统代理（无代理 / 自动 / 手动）翻译为子进程可识别的
    // POSIX 环境变量。所有非 sandbox 路径都注入这一份基线，sandbox 路径
    // 由内部 proxyLease 决定（其 HTTP_PROXY/HTTPS_PROXY 指向沙箱本机
    // 监听端口，避免穿透）。
    final userProxyEnvironment = SystemProxyResolver.instance
        .resolveSubprocessEnvironment();
    final baseMetadata = <String, Object?>{
      'sandbox_enabled': settings.enabled,
      'sandbox_tool_name': toolName,
      if (userProxyEnvironment.isNotEmpty)
        'user_proxy_env_keys': userProxyEnvironment.keys.toList(
          growable: false,
        ),
    };
    final shouldSandboxTool = settings.shouldSandboxBuiltinTool(toolName);
    final overrideMetadata = <String, Object?>{
      if (dangerouslyDisableSandbox) 'sandbox_override_requested': true,
    };
    // 所有「不进沙箱」的分支只在 metadata 上有差别，其余启动参数完全相同。
    AiSandboxLaunchSpec unsandboxed(Map<String, Object?> metadata) {
      return AiSandboxLaunchSpec.unsandboxed(
        executable: shellExecutable,
        arguments: shellArguments,
        workingDirectory: normalizedWorkingDirectory,
        environment: userProxyEnvironment,
        metadata: metadata,
      );
    }

    if (!settings.enabled || !shouldSandboxTool) {
      return unsandboxed(<String, Object?>{
        ...baseMetadata,
        ...overrideMetadata,
        if (dangerouslyDisableSandbox) 'sandbox_override_effective': false,
        if (dangerouslyDisableSandbox)
          'sandbox_override_reason': settings.enabled
              ? 'tool_not_sandboxed'
              : 'sandbox_disabled',
      });
    }
    if (dangerouslyDisableSandbox) {
      if (!settings.allowUnsandboxedCommands) {
        return AiSandboxLaunchSpec.blocked(
          executable: shellExecutable,
          arguments: shellArguments,
          workingDirectory: normalizedWorkingDirectory,
          reason:
              'dangerouslyDisableSandbox was requested, but OpenHand sandbox settings do not allow unsandboxed commands.',
          metadata: <String, Object?>{
            ...baseMetadata,
            ...overrideMetadata,
            'sandbox_override_denied': true,
          },
        );
      }
      return unsandboxed(<String, Object?>{
        ...baseMetadata,
        ...overrideMetadata,
        'sandbox_override_effective': true,
        'sandbox_override_reason': 'dangerouslyDisableSandbox',
      });
    }

    final excluded = settings.matchingExcludedCommand(command);
    if (excluded != null) {
      if (settings.allowUnsandboxedCommands) {
        return unsandboxed(<String, Object?>{
          ...baseMetadata,
          'sandbox_excluded': true,
          'sandbox_excluded_rule_id': excluded.id,
          'sandbox_excluded_rule_pattern': excluded.pattern,
        });
      }
      return AiSandboxLaunchSpec.blocked(
        executable: shellExecutable,
        arguments: shellArguments,
        workingDirectory: normalizedWorkingDirectory,
        reason:
            'Command matched sandbox exclusion rule "${excluded.pattern}", but unsandboxed commands are disabled.',
        metadata: baseMetadata,
      );
    }

    final status = await detectEnvironment();
    if (!status.available) {
      if (settings.failIfUnavailable || !settings.allowUnsandboxedCommands) {
        return AiSandboxLaunchSpec.blocked(
          executable: shellExecutable,
          arguments: shellArguments,
          workingDirectory: normalizedWorkingDirectory,
          reason: status.unavailableReason,
          metadata: <String, Object?>{
            ...baseMetadata,
            'sandbox_platform': status.platform,
            'sandbox_backend': status.backend,
          },
        );
      }
      return unsandboxed(<String, Object?>{
        ...baseMetadata,
        'sandbox_unavailable_reason': status.unavailableReason,
      });
    }

    if (settings.provider == AiSandboxProvider.e2b) {
      return AiSandboxLaunchSpec(
        executable: '/bin/bash',
        arguments: <String>['-l', '-c', command],
        workingDirectory: settings.e2b.commandWorkingDirectory,
        environment: const <String, String>{},
        applied: true,
        blocked: false,
        remote: true,
        metadata: <String, Object?>{
          ...baseMetadata,
          'sandbox_applied': true,
          'sandbox_platform': status.platform,
          'sandbox_backend': status.backend,
          'sandbox_filesystem_scope': 'remote',
          'sandbox_allowed_domain_count': settings.allowedDomains.length,
          'sandbox_denied_domain_count': settings.deniedDomains.length,
          'sandbox_network_direct_blocked':
              !settings.e2b.allowInternetAccess ||
              (!settings.allowNetworkWhenNoDomainRules &&
                  !settings.hasDomainRules &&
                  settings.e2b.allowOut.isEmpty &&
                  settings.e2b.denyOut.isEmpty &&
                  settings.e2b.networkRules.isEmpty),
          'sandbox_domain_filter_enforced':
              settings.hasDomainRules ||
              settings.e2b.allowOut.isNotEmpty ||
              settings.e2b.denyOut.isNotEmpty ||
              settings.e2b.networkRules.isNotEmpty,
        },
      );
    }

    if (!await isDirectoryPath(normalizedWorkingDirectory, followLinks: true)) {
      return AiSandboxLaunchSpec.blocked(
        executable: shellExecutable,
        arguments: shellArguments,
        workingDirectory: normalizedWorkingDirectory,
        reason:
            'Sandbox working directory does not exist: $normalizedWorkingDirectory',
        metadata: <String, Object?>{
          ...baseMetadata,
          'sandbox_platform': status.platform,
          'sandbox_backend': status.backend,
        },
      );
    }
    if (!_isSafeWritableWorkspaceRoot(normalizedWorkingDirectory)) {
      return AiSandboxLaunchSpec.blocked(
        executable: shellExecutable,
        arguments: shellArguments,
        workingDirectory: normalizedWorkingDirectory,
        reason: _unsafeWritableRootReason,
        metadata: <String, Object?>{
          ...baseMetadata,
          'sandbox_platform': status.platform,
          'sandbox_backend': status.backend,
          'sandbox_unsafe_working_directory': normalizedWorkingDirectory,
        },
      );
    }

    if (Platform.isLinux &&
        settings.hasDomainRules &&
        settings.failIfUnavailable) {
      return AiSandboxLaunchSpec.blocked(
        executable: shellExecutable,
        arguments: shellArguments,
        workingDirectory: normalizedWorkingDirectory,
        reason: _linuxDomainFilterUnavailableReason,
        metadata: <String, Object?>{
          ...baseMetadata,
          'sandbox_platform': status.platform,
          'sandbox_backend': status.backend,
          'sandbox_allowed_domain_count': settings.allowedDomains.length,
          'sandbox_denied_domain_count': settings.deniedDomains.length,
          'sandbox_network_direct_blocked': false,
          'sandbox_domain_filter_enforced': false,
          'sandbox_domain_filter_warning': _linuxDomainFilterUnavailableReason,
        },
      );
    }

    final AiSandboxProxyLease? proxyLease;
    try {
      proxyLease = settings.hasDomainRules
          ? await _proxyService.start(settings: settings)
          : null;
    } on AiSandboxProxyStartException catch (error) {
      if (settings.failIfUnavailable || !settings.allowUnsandboxedCommands) {
        return AiSandboxLaunchSpec.blocked(
          executable: shellExecutable,
          arguments: shellArguments,
          workingDirectory: normalizedWorkingDirectory,
          reason: error.message,
          metadata: <String, Object?>{
            ...baseMetadata,
            'sandbox_proxy_unavailable_reason': error.message,
          },
        );
      }
      return unsandboxed(<String, Object?>{
        ...baseMetadata,
        'sandbox_proxy_unavailable_reason': error.message,
      });
    }
    Future<void> closeProxyAfterLaunchFailure(String reason) async {
      final lease = proxyLease;
      if (lease == null) return;
      await lease.closeBounded(
        logTag: 'ai_sandbox_service',
        logWhere: '关闭沙箱启动代理（$reason）',
      );
    }

    // sandbox 启用时，沙箱内部 proxy 决定子进程网络出口；用户级
    // HTTP_PROXY/HTTPS_PROXY 不能穿透到沙箱内的子进程，否则会绕过
    // 域名 allow/deny。仅当沙箱未启 lease 时回退到用户代理 env。
    final environment = proxyLease != null
        ? proxyLease.environment
        : userProxyEnvironment;
    try {
      Map<String, Object?> appliedMetadata({
        required bool networkDirectBlocked,
        required bool domainFilterEnforced,
        String? domainFilterWarning,
      }) => <String, Object?>{
        ...baseMetadata,
        'sandbox_applied': true,
        'sandbox_platform': status.platform,
        'sandbox_backend': status.backend,
        'sandbox_filesystem_rule_count': settings.filesystemRules.length,
        'sandbox_working_directory_writable': true,
        'sandbox_allowed_domain_count': settings.allowedDomains.length,
        'sandbox_denied_domain_count': settings.deniedDomains.length,
        if (proxyLease != null) ...proxyLease.metadata,
        'sandbox_network_direct_blocked': networkDirectBlocked,
        'sandbox_domain_filter_enforced': domainFilterEnforced,
        if (domainFilterWarning != null)
          'sandbox_domain_filter_warning': domainFilterWarning,
      };
      if (Platform.isMacOS) {
        final profile = _buildMacSandboxProfile(
          normalizedWorkingDirectory,
          proxyLease,
        );
        return AiSandboxLaunchSpec(
          executable: 'sandbox-exec',
          arguments: <String>[
            '-p',
            profile,
            shellExecutable,
            ...shellArguments,
          ],
          workingDirectory: normalizedWorkingDirectory,
          environment: environment,
          applied: true,
          blocked: false,
          proxyLease: proxyLease,
          metadata: appliedMetadata(
            networkDirectBlocked: proxyLease != null,
            domainFilterEnforced: proxyLease != null,
          ),
        );
      }

      if (Platform.isLinux) {
        final args = await _buildLinuxBubblewrapArgs(
          shellExecutable: shellExecutable,
          shellArguments: shellArguments,
          workingDirectory: normalizedWorkingDirectory,
        );
        return AiSandboxLaunchSpec(
          executable: 'bwrap',
          arguments: args,
          workingDirectory: normalizedWorkingDirectory,
          environment: environment,
          applied: true,
          blocked: false,
          proxyLease: proxyLease,
          metadata: appliedMetadata(
            networkDirectBlocked: false,
            domainFilterEnforced: false,
            domainFilterWarning: proxyLease == null
                ? null
                : _linuxDomainFilterBestEffortWarning,
          ),
        );
      }

      await closeProxyAfterLaunchFailure('平台不支持');
      return AiSandboxLaunchSpec.blocked(
        executable: shellExecutable,
        arguments: shellArguments,
        workingDirectory: normalizedWorkingDirectory,
        reason:
            'Sandbox backend is not available on ${Platform.operatingSystem}.',
        metadata: baseMetadata,
      );
    } catch (_) {
      await closeProxyAfterLaunchFailure('构建启动参数失败');
      rethrow;
    }
  }

  Future<AiE2bCommandHandle> startRemoteCommand({
    required String command,
    required AiSandboxLaunchSpec launchSpec,
    required int timeoutMs,
    required bool keepStdinOpen,
    void Function(String chunk)? onStdout,
    void Function(String chunk)? onStderr,
  }) {
    if (!launchSpec.remote) {
      throw ArgumentError.value(launchSpec.remote, 'launchSpec.remote');
    }
    return _e2bService.startCommand(
      command: command,
      workingDirectory: launchSpec.workingDirectory,
      environment: launchSpec.environment,
      timeoutMs: timeoutMs,
      keepStdinOpen: keepStdinOpen,
      onStdout: onStdout,
      onStderr: onStderr,
    );
  }

  Future<void> shutdown() => _e2bService.shutdown();

  Future<_LinuxSandboxPackageManager?> _resolveLinuxPackageManager() async {
    if (!Platform.isLinux) return null;
    const managers = <_LinuxSandboxPackageManager>[
      _LinuxSandboxPackageManager(
        executable: 'apt-get',
        installArguments: <String>['install', '-y', 'bubblewrap'],
        updateArguments: <String>[
          'install',
          '--only-upgrade',
          '-y',
          'bubblewrap',
        ],
        uninstallArguments: <String>['remove', '-y', 'bubblewrap'],
      ),
      _LinuxSandboxPackageManager(
        executable: 'dnf',
        installArguments: <String>['install', '-y', 'bubblewrap'],
        updateArguments: <String>['upgrade', '-y', 'bubblewrap'],
        uninstallArguments: <String>['remove', '-y', 'bubblewrap'],
      ),
      _LinuxSandboxPackageManager(
        executable: 'yum',
        installArguments: <String>['install', '-y', 'bubblewrap'],
        updateArguments: <String>['update', '-y', 'bubblewrap'],
        uninstallArguments: <String>['remove', '-y', 'bubblewrap'],
      ),
      _LinuxSandboxPackageManager(
        executable: 'pacman',
        installArguments: <String>['-S', '--noconfirm', 'bubblewrap'],
        updateArguments: <String>['-S', '--noconfirm', 'bubblewrap'],
        uninstallArguments: <String>['-R', '--noconfirm', 'bubblewrap'],
      ),
      _LinuxSandboxPackageManager(
        executable: 'zypper',
        installArguments: <String>[
          '--non-interactive',
          'install',
          'bubblewrap',
        ],
        updateArguments: <String>['--non-interactive', 'update', 'bubblewrap'],
        uninstallArguments: <String>[
          '--non-interactive',
          'remove',
          'bubblewrap',
        ],
      ),
      _LinuxSandboxPackageManager(
        executable: 'apk',
        installArguments: <String>['add', 'bubblewrap'],
        updateArguments: <String>['upgrade', 'bubblewrap'],
        uninstallArguments: <String>['del', 'bubblewrap'],
      ),
    ];
    for (final manager in managers) {
      if (await _commandExists(manager.executable)) return manager;
    }
    return null;
  }

  Future<String> _readBubblewrapVersion() async {
    final result = await runTrackedProcessOrFailed(
      'bwrap',
      const <String>['--version'],
      timeout: const Duration(seconds: 3),
      tag: 'ai_sandbox.version',
    );
    if (result.exitCode != 0) return '';
    return '${result.stdout}'.trim();
  }

  Future<bool> _hasBubblewrapUpdate(_LinuxSandboxPackageManager manager) async {
    if (manager.executable == 'apt-get') {
      if (!await _commandExists('apt-cache')) return false;
      final result = await runTrackedProcessOrFailed(
        'apt-cache',
        const <String>['policy', 'bubblewrap'],
        tag: 'ai_sandbox.update_probe',
      );
      if (result.exitCode != 0) return false;
      final output = '${result.stdout}';
      final installed = RegExp(
        r'^\s*Installed:\s*(\S+)',
        multiLine: true,
      ).firstMatch(output)?.group(1);
      final candidate = RegExp(
        r'^\s*Candidate:\s*(\S+)',
        multiLine: true,
      ).firstMatch(output)?.group(1);
      return installed != null &&
          candidate != null &&
          installed != '(none)' &&
          candidate != '(none)' &&
          installed != candidate;
    }
    final probe = switch (manager.executable) {
      'dnf' || 'yum' => <String>[
        manager.executable,
        '--cacheonly',
        'check-update',
        'bubblewrap',
      ],
      'pacman' => const <String>['pacman', '-Qu', 'bubblewrap'],
      'zypper' => const <String>[
        'zypper',
        '--non-interactive',
        'list-updates',
        '--type',
        'package',
        'bubblewrap',
      ],
      'apk' => const <String>['apk', 'version', '-l', '<', 'bubblewrap'],
      _ => const <String>[],
    };
    if (probe.isEmpty) return false;
    final result = await runTrackedProcessOrFailed(
      probe.first,
      probe.skip(1).toList(growable: false),
      timeout: const Duration(seconds: 5),
      tag: 'ai_sandbox.update_probe',
    );
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    if (manager.executable == 'dnf' || manager.executable == 'yum') {
      return result.exitCode == 100 && output.contains('bubblewrap');
    }
    return result.exitCode == 0 && output.contains('bubblewrap');
  }

  Future<bool> _commandExists(String command) async {
    final directCandidates = Platform.isMacOS && command == 'sandbox-exec'
        ? const <String>['/usr/bin/sandbox-exec']
        : command == 'bwrap'
        ? const <String>['/usr/bin/bwrap', '/usr/local/bin/bwrap']
        : const <String>[];
    for (final candidate in directCandidates) {
      if (await isRegularFilePath(candidate, followLinks: true)) return true;
    }
    final result = await runProcessWithTimeout(
      Platform.isWindows ? 'where' : '/usr/bin/env',
      Platform.isWindows
          ? <String>[command]
          : <String>['sh', '-lc', 'command -v ${posixShellQuote(command)}'],
      timeout: const Duration(seconds: 2),
      tag: 'ai_sandbox_service',
    );
    if (result == null || result.exitCode != 0) return false;
    return '${result.stdout}'.trim().isNotEmpty;
  }

  String _buildMacSandboxProfile(
    String workingDirectory,
    AiSandboxProxyLease? proxyLease,
  ) {
    final writeFilters = <String>{
      _profileSubpath('/tmp'),
      _profileSubpath('/private/tmp'),
      _profileSubpath('/var/folders'),
      _profileSubpath(workingDirectory),
    };
    final readOnlyDenyFilters = <String>{};
    for (final rule in settings.filesystemRules) {
      final path = rule.path.trim();
      if (path.isEmpty) continue;
      final filter = rule.matchMode == AiCommandMatchMode.regex
          ? _profileRegex(path)
          : _profileSubpath(_resolveFilesystemPath(path, workingDirectory));
      if (rule.accessMode == AiSandboxFileAccessMode.readWrite) {
        writeFilters.add(filter);
      } else {
        readOnlyDenyFilters.add(filter);
      }
    }
    final buffer = StringBuffer()
      ..writeln('(version 1)')
      ..writeln('(allow default)')
      ..writeln('(deny file-write*)');
    if (writeFilters.isNotEmpty) {
      buffer
        ..writeln('(allow file-write*')
        ..writeln(writeFilters.map((item) => '  $item').join('\n'))
        ..writeln(')');
    }
    if (readOnlyDenyFilters.isNotEmpty) {
      buffer
        ..writeln('(deny file-write*')
        ..writeln(readOnlyDenyFilters.map((item) => '  $item').join('\n'))
        ..writeln(')');
    }
    if (proxyLease != null) {
      buffer.writeln('(deny network*)');
      buffer.writeln('(allow network-outbound');
      for (final port in proxyLease.loopbackPorts) {
        buffer.writeln('  (remote tcp "localhost:$port")');
        buffer.writeln('  (remote tcp "127.0.0.1:$port")');
      }
      buffer.writeln(')');
    } else if (!settings.allowNetworkWhenNoDomainRules &&
        !settings.hasDomainRules) {
      buffer.writeln('(deny network*)');
    }
    return buffer.toString().trimRight();
  }

  Future<List<String>> _buildLinuxBubblewrapArgs({
    required String shellExecutable,
    required List<String> shellArguments,
    required String workingDirectory,
  }) async {
    final args = <String>[
      '--die-with-parent',
      '--ro-bind',
      '/',
      '/',
      '--dev',
      '/dev',
      '--proc',
      '/proc',
      '--tmpfs',
      '/tmp',
      '--chdir',
      workingDirectory,
    ];
    if (!settings.allowNetworkWhenNoDomainRules && !settings.hasDomainRules) {
      args.add('--unshare-net');
    }
    final writableBinds = <String>{workingDirectory};
    final readOnlyBinds = <String>{};
    final probeStopwatch = Stopwatch()..start();
    for (final rule in settings.filesystemRules) {
      if (probeStopwatch.elapsed >= _sandboxPathProbeTotalTimeout) break;
      if (rule.matchMode == AiCommandMatchMode.regex) continue;
      final resolved = _resolveFilesystemPath(rule.path, workingDirectory);
      if (rule.accessMode == AiSandboxFileAccessMode.readWrite) {
        final existing = await _existingWritableBindPath(
          resolved,
          stopwatch: probeStopwatch,
        );
        if (existing == null) continue;
        if (_isSafeWritableWorkspaceRoot(existing)) {
          writableBinds.add(existing);
        }
      } else {
        final existing = await _existingExactPath(
          resolved,
          stopwatch: probeStopwatch,
        );
        if (existing == null) continue;
        readOnlyBinds.add(existing);
      }
    }
    for (final writable in writableBinds) {
      args.addAll(<String>['--bind', writable, writable]);
    }
    for (final readOnly in readOnlyBinds) {
      args.addAll(<String>['--ro-bind', readOnly, readOnly]);
    }
    args.addAll(<String>[shellExecutable, ...shellArguments]);
    return args;
  }

  String _normalizeWorkingDirectory(String workingDirectory) {
    final trimmed = workingDirectory.trim();
    if (trimmed.isEmpty) return OpenHandPaths.applicationDirectoryPath();
    return OpenHandPaths.normalizePath(
      trimmed,
      defaultPath: OpenHandPaths.applicationDirectoryPath(),
    );
  }

  String _resolveFilesystemPath(String value, String workingDirectory) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return workingDirectory;
    if (trimmed == '~') return OpenHandPaths.homeDirectoryPath();
    if (trimmed.startsWith('~/')) {
      return p.normalize(
        p.join(OpenHandPaths.homeDirectoryPath(), trimmed.substring(2)),
      );
    }
    if (p.isAbsolute(trimmed)) return p.normalize(trimmed);
    return p.normalize(p.join(workingDirectory, trimmed));
  }

  Future<String?> _existingWritableBindPath(
    String resolved, {
    required Stopwatch stopwatch,
  }) async {
    final type = await _probeSandboxPathType(resolved, stopwatch: stopwatch);
    if (type == null) return null;
    if (type != FileSystemEntityType.notFound) return resolved;
    final parent = p.dirname(resolved);
    final parentType = await _probeSandboxPathType(
      parent,
      stopwatch: stopwatch,
      followLinks: true,
    );
    if (parentType == FileSystemEntityType.directory) {
      return parent;
    }
    return null;
  }

  Future<String?> _existingExactPath(
    String resolved, {
    required Stopwatch stopwatch,
  }) async {
    final type = await _probeSandboxPathType(resolved, stopwatch: stopwatch);
    return type == null || type == FileSystemEntityType.notFound
        ? null
        : resolved;
  }

  Future<FileSystemEntityType?> _probeSandboxPathType(
    String path, {
    required Stopwatch stopwatch,
    bool followLinks = false,
  }) async {
    try {
      return await FileSystemEntity.type(
        path,
        followLinks: followLinks,
      ).timeout(_nextSandboxPathProbeTimeout(stopwatch));
    } on FileSystemException {
      return null;
    } on TimeoutException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  Duration _nextSandboxPathProbeTimeout(Stopwatch stopwatch) {
    final remaining = _sandboxPathProbeTotalTimeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) return const Duration(microseconds: 1);
    return remaining < _sandboxPathProbeIdleTimeout
        ? remaining
        : _sandboxPathProbeIdleTimeout;
  }

  bool _isSafeWritableWorkspaceRoot(String value) {
    final normalized = p.normalize(value.trim());
    if (normalized.isEmpty) return false;
    final root = p.normalize(p.rootPrefix(normalized));
    if (root.isNotEmpty && normalized == root) return false;
    final home = p.normalize(OpenHandPaths.homeDirectoryPath());
    if (home.isNotEmpty && normalized == home) return false;
    return true;
  }

  String _profileSubpath(String value) {
    return '(subpath "${_escapeProfileString(value)}")';
  }

  String _profileRegex(String value) {
    return '(regex #"${_escapeProfileString(value)}")';
  }

  String _escapeProfileString(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }
}
