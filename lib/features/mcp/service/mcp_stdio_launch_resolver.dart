import 'dart:async';
import 'dart:io';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/mcp_server.dart';
import 'mcp_node_package_resolver.dart';
import 'mcp_stdio_cache.dart';
import 'mcp_stdio_io_utils.dart';

const Duration _loginShellProbeTimeout = Duration(seconds: 3);
const int _loginShellProbeMaxStdoutBytes = 64 * kBytesPerKiB;
const int _loginShellProbeMaxStderrBytes = 16 * kBytesPerKiB;
const int _pathProbeLimit = 256;
const String _loginPathMarker = '__OPENHAND_MCP_PATH__';
final RegExp _lineBreaksPattern = RegExp(r'[\r\n]+');

String? _cachedLoginEnvironmentPath;
Completer<String>? _loginEnvironmentPathProbe;

String get mcpCachedLoginEnvironmentPath => _cachedLoginEnvironmentPath ?? '';
String get mcpProcessEnvironmentPath => Platform.environment['PATH'] ?? '';

final class McpStdioLaunch {
  McpStdioLaunch({
    required this.executable,
    required List<String> args,
    required Map<String, String> environment,
    this.runInShell = false,
  }) : args = List<String>.unmodifiable(args),
       environment = Map<String, String>.unmodifiable(environment);

  final String executable;
  final List<String> args;
  final Map<String, String> environment;
  final bool runInShell;
}

/// 统一解析 STDIO MCP 的可执行文件、参数和运行环境。
Future<McpStdioLaunch> resolveMcpStdioLaunch(McpServer server) async {
  final tokens = tokenizeMcpShellCommand(server.command);
  if (tokens.isEmpty) {
    throw const FormatException('MCP stdio 启动命令不能为空。');
  }

  final rawCommand = tokens.first;
  final inlineArgs = tokens.length > 1 ? tokens.sublist(1) : const <String>[];
  var executable = rawCommand;
  var args = <String>[...inlineArgs, ...server.args];
  final home = OpenHandPaths.environmentHomeDirectoryPath();

  final separator = Platform.isWindows ? ';' : ':';
  final originalSegments = splitTrimmedNonEmpty(
    mcpProcessEnvironmentPath,
    separator: separator,
  );
  final heuristicSegments = <String>[];
  if (Platform.isMacOS) {
    heuristicSegments.addAll(const <String>[
      '/opt/homebrew/bin',
      '/opt/homebrew/sbin',
      '/usr/local/bin',
      '/usr/local/sbin',
    ]);
  } else if (Platform.isLinux) {
    heuristicSegments.addAll(const <String>[
      '/usr/local/bin',
      '/usr/local/sbin',
      '/snap/bin',
    ]);
  }
  if (home != null && home.isNotEmpty) {
    heuristicSegments.addAll(
      Platform.isWindows
          ? <String>[
              '$home\\AppData\\Roaming\\npm',
              '$home\\.cargo\\bin',
              '$home\\.bun\\bin',
              '$home\\.deno\\bin',
              '$home\\.local\\bin',
            ]
          : <String>[
              '$home/.npm-global/bin',
              '$home/.local/bin',
              '$home/.cargo/bin',
              '$home/.bun/bin',
              '$home/.deno/bin',
              '$home/.volta/bin',
            ],
    );
  }

  final shellSegments = <String>[];
  if (!Platform.isWindows) {
    final shellPath = await _probeLoginEnvironmentPath();
    if (shellPath.isNotEmpty) {
      shellSegments.addAll(
        splitTrimmedNonEmpty(shellPath, separator: separator),
      );
    }
  }

  final mergedSegments = <String>[];
  final seen = <String>{};
  for (final segment in <String>[
    ...shellSegments,
    ...originalSegments,
    ...heuristicSegments,
  ]) {
    final key = Platform.isWindows ? segment.toLowerCase() : segment;
    if (seen.add(key)) mergedSegments.add(segment);
  }
  final mergedPath = mergedSegments.join(separator);

  if (!Platform.isWindows && isMcpNpxCommand(rawCommand)) {
    final packageArgIndex = firstMcpNpxPackageArgIndex(args);
    if (packageArgIndex >= 0) {
      final resolved = await _resolveNpxPackage(
        args[packageArgIndex],
        homeDirectory: home,
      );
      if (resolved != null) {
        final extraArgs = packageArgIndex + 1 < args.length
            ? args.sublist(packageArgIndex + 1)
            : const <String>[];
        return McpStdioLaunch(
          executable: resolved.nodeBin,
          args: <String>[resolved.entryScript, ...extraArgs],
          environment: <String, String>{
            if (mergedPath.isNotEmpty) 'PATH': mergedPath,
            ...await mcpStdioIsolatedCacheEnv(),
          },
        );
      }
    }
  }

  final containsSeparator =
      rawCommand.contains('/') ||
      (Platform.isWindows && rawCommand.contains('\\'));
  if (!containsSeparator) {
    final candidates = <String>[rawCommand];
    if (Platform.isWindows) {
      final lower = rawCommand.toLowerCase();
      for (final extension in const <String>['.cmd', '.bat', '.exe', '.com']) {
        if (!lower.endsWith(extension)) candidates.add('$rawCommand$extension');
      }
    }

    String? resolvedExecutable;
    for (final directory in mergedSegments.take(_pathProbeLimit)) {
      for (final candidate in candidates) {
        final path = directory.endsWith(Platform.pathSeparator)
            ? '$directory$candidate'
            : '$directory${Platform.pathSeparator}$candidate';
        try {
          final type = await FileSystemEntity.type(
            path,
          ).timeout(mcpStdioFileOperationTimeout);
          if (type == FileSystemEntityType.file) {
            resolvedExecutable = path;
            break;
          }
        } catch (_) {
          // 无法访问的 PATH 候选直接跳过。
        }
      }
      if (resolvedExecutable != null) break;
    }

    if (resolvedExecutable != null) {
      executable = resolvedExecutable;
    } else if (!Platform.isWindows) {
      executable = await resolveMcpLoginShell();
      args = <String>[
        '-lc',
        'exec ${quoteMcpShellToken(rawCommand)} "\$@"',
        '_',
        ...args,
      ];
    }
  }

  return McpStdioLaunch(
    executable: executable,
    args: args,
    environment: <String, String>{
      if (mergedPath.isNotEmpty) 'PATH': mergedPath,
      ...await mcpStdioIsolatedCacheEnv(),
    },
    runInShell: Platform.isWindows,
  );
}

Future<String> _probeLoginEnvironmentPath() {
  final cached = _cachedLoginEnvironmentPath;
  if (cached != null) return Future<String>.value(cached);
  final activeProbe = _loginEnvironmentPathProbe;
  if (activeProbe != null) return activeProbe.future;
  final completer = Completer<String>();
  _loginEnvironmentPathProbe = completer;

  () async {
    var result = '';
    try {
      for (final candidate in await existingMcpLoginShells()) {
        try {
          final probe = await runProcessWithTimeout(
            candidate,
            const <String>['-ilc', 'printf "\\n$_loginPathMarker%s" "\$PATH"'],
            timeout: _loginShellProbeTimeout,
            tag: 'mcp.stdio.login_shell_path',
            maxStdoutBytes: _loginShellProbeMaxStdoutBytes,
            maxStderrBytes: _loginShellProbeMaxStderrBytes,
          );
          final output = '${probe?.stdout ?? ''}';
          final markerIndex = output.lastIndexOf(_loginPathMarker);
          final path = markerIndex < 0
              ? null
              : nullIfBlank(
                  output.substring(markerIndex + _loginPathMarker.length),
                );
          if (path != null) {
            result = path;
            break;
          }
        } catch (error, stack) {
          silentLog('mcp_stdio', '探测登录 Shell 路径/$candidate', error, stack);
        }
      }
    } catch (error, stack) {
      silentLog('mcp_stdio', '探测登录 Shell 路径', error, stack);
    }
    _cachedLoginEnvironmentPath = result;
    completer.complete(result);
  }();
  return completer.future;
}

Future<McpNodePackageResolution?> _resolveNpxPackage(
  String packageName, {
  required String? homeDirectory,
}) async {
  final cleanName = normalizeMcpNodePackageName(packageName);
  if (cleanName == null) return null;
  final installed = await resolveInstalledMcpNodePackage(
    cleanName,
    homeDirectory: homeDirectory,
  );
  if (installed != null) return installed;

  try {
    final shell = await resolveMcpLoginShell();
    final result = await runProcessWithTimeout(
      shell,
      const <String>['-lc', 'command -v node && npm root -g'],
      timeout: const Duration(seconds: 8),
      tag: 'mcp_stdio.login_shell_probe',
      maxStdoutBytes: _loginShellProbeMaxStdoutBytes,
      maxStderrBytes: _loginShellProbeMaxStderrBytes,
    );
    if (result == null || result.exitCode != 0) return null;
    final lines = splitTrimmedNonEmpty(
      '${result.stdout}',
      separator: _lineBreaksPattern,
    );
    if (lines.length < 2) return null;
    return await resolveMcpNodePackageCandidate(
      nodeBin: lines.first,
      packageDirectory: '${lines[1]}/$cleanName',
    );
  } catch (error, stack) {
    silentLog('mcp_stdio', '探测登录 Shell 软件包', error, stack);
    return null;
  }
}
