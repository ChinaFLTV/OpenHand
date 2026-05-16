import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../model/ai_deny_command_rule.dart';
import '../../model/ai_sandbox_settings.dart';
import 'ai_sandbox_proxy_service.dart';

class AiSandboxEnvironmentStatus {
  const AiSandboxEnvironmentStatus({
    required this.platform,
    required this.supported,
    required this.available,
    required this.backend,
    required this.missingDependencies,
    required this.warnings,
  });

  final String platform;
  final bool supported;
  final bool available;
  final String backend;
  final List<String> missingDependencies;
  final List<String> warnings;

  String get unavailableReason {
    if (available) return '';
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
    };
  }
}

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
  final Map<String, Object?> metadata;
  final AiSandboxProxyLease? proxyLease;
}

class AiSandboxService {
  AiSandboxService({AiSandboxSettings? settings})
    : settings = settings ?? AiSandboxSettings.defaults();

  static const String _linuxDomainFilterUnavailableReason =
      'Linux bubblewrap cannot strictly enforce sandbox domain allow/deny rules yet because direct network access cannot be restricted to the OpenHand local proxy without an additional network bridge.';
  static const String _linuxDomainFilterBestEffortWarning =
      'Linux sandbox domain rules are best-effort here: OpenHand injects proxy environment variables, but bubblewrap does not block direct network bypass in this mode.';

  AiSandboxSettings settings;
  final AiSandboxProxyService _proxyService = AiSandboxProxyService();
  AiSandboxEnvironmentStatus? _cachedStatus;

  Future<AiSandboxEnvironmentStatus> detectEnvironment({
    bool refresh = false,
  }) async {
    if (!refresh && _cachedStatus != null) return _cachedStatus!;
    final platform = Platform.operatingSystem;
    final warnings = <String>[];
    final missing = <String>[];
    String backend = '';
    var supported = false;

    if (Platform.isMacOS) {
      supported = true;
      backend = 'sandbox-exec';
      if (!await _commandExists('sandbox-exec')) missing.add('sandbox-exec');
    } else if (Platform.isLinux) {
      supported = true;
      backend = 'bubblewrap';
      if (!await _commandExists('bwrap')) missing.add('bwrap');
      if (!await _commandExists('sh')) missing.add('sh');
      if (settings.filesystemRules.any(
        (rule) => rule.matchMode == AiDenyCommandMatchMode.regex,
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
    );
    _cachedStatus = status;
    return status;
  }

  Future<AiSandboxActionResult> installEnvironment() async {
    if (Platform.isMacOS) {
      final status = await detectEnvironment(refresh: true);
      if (status.available) {
        return const AiSandboxActionResult(
          success: true,
          message:
              'macOS sandbox-exec is available; no installation is needed.',
        );
      }
      return const AiSandboxActionResult(
        success: false,
        message:
            'macOS sandbox-exec is provided by the system and cannot be installed by OpenHand.',
      );
    }
    if (Platform.isLinux) {
      return const AiSandboxActionResult(
        success: false,
        message: 'Install bubblewrap with your system package manager.',
        command: 'sudo apt-get update && sudo apt-get install -y bubblewrap',
      );
    }
    return AiSandboxActionResult(
      success: false,
      message:
          'Sandbox installation is not supported on ${Platform.operatingSystem}.',
    );
  }

  Future<AiSandboxActionResult> updateEnvironment() async {
    if (Platform.isMacOS) {
      return const AiSandboxActionResult(
        success: true,
        message: 'macOS sandbox-exec is updated with the operating system.',
      );
    }
    if (Platform.isLinux) {
      return const AiSandboxActionResult(
        success: false,
        message: 'Update bubblewrap with your system package manager.',
        command:
            'sudo apt-get update && sudo apt-get install --only-upgrade -y bubblewrap',
      );
    }
    return AiSandboxActionResult(
      success: false,
      message:
          'Sandbox update is not supported on ${Platform.operatingSystem}.',
    );
  }

  Future<AiSandboxActionResult> uninstallEnvironment() async {
    if (Platform.isMacOS) {
      return const AiSandboxActionResult(
        success: false,
        message:
            'macOS sandbox-exec is a system component and cannot be uninstalled by OpenHand.',
      );
    }
    if (Platform.isLinux) {
      return const AiSandboxActionResult(
        success: false,
        message: 'Remove bubblewrap with your system package manager.',
        command: 'sudo apt-get remove -y bubblewrap',
      );
    }
    return AiSandboxActionResult(
      success: false,
      message:
          'Sandbox uninstall is not supported on ${Platform.operatingSystem}.',
    );
  }

  Future<AiSandboxLaunchSpec> prepareShellCommand({
    required String toolName,
    required String command,
    required String shellExecutable,
    required List<String> shellArguments,
    required String workingDirectory,
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
    if (!settings.enabled || !settings.shouldSandboxBuiltinTool(toolName)) {
      return AiSandboxLaunchSpec.unsandboxed(
        executable: shellExecutable,
        arguments: shellArguments,
        workingDirectory: normalizedWorkingDirectory,
        environment: userProxyEnvironment,
        metadata: baseMetadata,
      );
    }

    final excluded = settings.matchingExcludedCommand(command);
    if (excluded != null) {
      if (settings.allowUnsandboxedCommands) {
        return AiSandboxLaunchSpec.unsandboxed(
          executable: shellExecutable,
          arguments: shellArguments,
          workingDirectory: normalizedWorkingDirectory,
          environment: userProxyEnvironment,
          metadata: <String, Object?>{
            ...baseMetadata,
            'sandbox_excluded': true,
            'sandbox_excluded_rule_id': excluded.id,
            'sandbox_excluded_rule_pattern': excluded.pattern,
          },
        );
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
      return AiSandboxLaunchSpec.unsandboxed(
        executable: shellExecutable,
        arguments: shellArguments,
        workingDirectory: normalizedWorkingDirectory,
        environment: userProxyEnvironment,
        metadata: <String, Object?>{
          ...baseMetadata,
          'sandbox_unavailable_reason': status.unavailableReason,
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
      return AiSandboxLaunchSpec.unsandboxed(
        executable: shellExecutable,
        arguments: shellArguments,
        workingDirectory: normalizedWorkingDirectory,
        environment: userProxyEnvironment,
        metadata: <String, Object?>{
          ...baseMetadata,
          'sandbox_proxy_unavailable_reason': error.message,
        },
      );
    }

    // sandbox 启用时，沙箱内部 proxy 决定子进程网络出口；用户级
    // HTTP_PROXY/HTTPS_PROXY 不能穿透到沙箱内的子进程，否则会绕过
    // 域名 allow/deny。仅当沙箱未启 lease 时回退到用户代理 env。
    final environment = proxyLease != null
        ? proxyLease.environment
        : userProxyEnvironment;
    if (Platform.isMacOS) {
      final profile = _buildMacSandboxProfile(
        normalizedWorkingDirectory,
        proxyLease,
      );
      return AiSandboxLaunchSpec(
        executable: 'sandbox-exec',
        arguments: <String>['-p', profile, shellExecutable, ...shellArguments],
        workingDirectory: normalizedWorkingDirectory,
        environment: environment,
        applied: true,
        blocked: false,
        proxyLease: proxyLease,
        metadata: <String, Object?>{
          ...baseMetadata,
          'sandbox_applied': true,
          'sandbox_platform': status.platform,
          'sandbox_backend': status.backend,
          'sandbox_filesystem_rule_count': settings.filesystemRules.length,
          'sandbox_allowed_domain_count': settings.allowedDomains.length,
          'sandbox_denied_domain_count': settings.deniedDomains.length,
          if (proxyLease != null) ...proxyLease.metadata,
          'sandbox_network_direct_blocked': proxyLease != null,
          'sandbox_domain_filter_enforced': proxyLease != null,
        },
      );
    }

    if (Platform.isLinux) {
      final args = _buildLinuxBubblewrapArgs(
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
        metadata: <String, Object?>{
          ...baseMetadata,
          'sandbox_applied': true,
          'sandbox_platform': status.platform,
          'sandbox_backend': status.backend,
          'sandbox_filesystem_rule_count': settings.filesystemRules.length,
          'sandbox_allowed_domain_count': settings.allowedDomains.length,
          'sandbox_denied_domain_count': settings.deniedDomains.length,
          if (proxyLease != null) ...proxyLease.metadata,
          'sandbox_network_direct_blocked': false,
          'sandbox_domain_filter_enforced': false,
          if (proxyLease != null)
            'sandbox_domain_filter_warning':
                _linuxDomainFilterBestEffortWarning,
        },
      );
    }

    return AiSandboxLaunchSpec.blocked(
      executable: shellExecutable,
      arguments: shellArguments,
      workingDirectory: normalizedWorkingDirectory,
      reason:
          'Sandbox backend is not available on ${Platform.operatingSystem}.',
      metadata: baseMetadata,
    );
  }

  Future<bool> _commandExists(String command) async {
    final directCandidates = Platform.isMacOS && command == 'sandbox-exec'
        ? const <String>['/usr/bin/sandbox-exec']
        : command == 'bwrap'
        ? const <String>['/usr/bin/bwrap', '/usr/local/bin/bwrap']
        : const <String>[];
    for (final candidate in directCandidates) {
      if (File(candidate).existsSync()) return true;
    }
    final result = await runProcessWithTimeout(
      Platform.isWindows ? 'where' : '/usr/bin/env',
      Platform.isWindows
          ? <String>[command]
          : <String>['sh', '-lc', 'command -v ${_quoteShell(command)}'],
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
    };
    final readOnlyDenyFilters = <String>{};
    for (final rule in settings.filesystemRules) {
      final path = rule.path.trim();
      if (path.isEmpty) continue;
      final filter = rule.matchMode == AiDenyCommandMatchMode.regex
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
      buffer.writeln('(allow network*');
      for (final port in proxyLease.loopbackPorts) {
        buffer.writeln('  (remote ip "localhost:$port")');
      }
      buffer.writeln(')');
    } else if (!settings.allowNetworkWhenNoDomainRules &&
        !settings.hasDomainRules) {
      buffer.writeln('(deny network*)');
    }
    return buffer.toString().trimRight();
  }

  List<String> _buildLinuxBubblewrapArgs({
    required String shellExecutable,
    required List<String> shellArguments,
    required String workingDirectory,
  }) {
    final args = <String>[
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
    for (final rule in settings.filesystemRules) {
      if (rule.accessMode != AiSandboxFileAccessMode.readWrite) continue;
      if (rule.matchMode == AiDenyCommandMatchMode.regex) continue;
      final resolved = _resolveFilesystemPath(rule.path, workingDirectory);
      final existing = _existingBindPath(resolved);
      if (existing == null) continue;
      args.addAll(<String>['--bind', existing, existing]);
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

  String? _existingBindPath(String resolved) {
    try {
      final type = FileSystemEntity.typeSync(resolved, followLinks: false);
      if (type != FileSystemEntityType.notFound) return resolved;
      final parent = p.dirname(resolved);
      if (Directory(parent).existsSync()) return parent;
    } catch (error, stack) {
      silentLog(
        'ai_sandbox_service',
        'resolve bind path $resolved',
        error,
        stack,
      );
    }
    return null;
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

  String _quoteShell(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }
}
