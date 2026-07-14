import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import 'mcp_stdio_mirror_policy.dart';

const String mcpNpmMirrorRegistry = 'https://registry.npmmirror.com';
const String mcpPypiMirrorIndex = 'https://pypi.tuna.tsinghua.edu.cn/simple';
const Duration mcpStdioFileOperationTimeout = Duration(seconds: 3);

/// stdio MCP 隔离包缓存根目录：~/.openhand/mcp/package-cache。
String mcpStdioIsolatedCacheRoot() =>
    p.join(OpenHandPaths.defaultMcpDirectoryPath(), 'package-cache');

Future<Map<String, String>> mcpStdioIsolatedCacheEnv() async {
  try {
    final root = mcpStdioIsolatedCacheRoot();
    final npmCache = p.join(root, 'npm');
    final npmPrefix = p.join(root, 'npm-prefix');
    final uvCache = p.join(root, 'uv');
    final pipCache = p.join(root, 'pip');
    final bunInstall = p.join(root, 'bun');
    final denoDir = p.join(root, 'deno');
    final pnpmStore = p.join(root, 'pnpm-store');
    final yarnCache = p.join(root, 'yarn');
    await Future.wait<Directory>(
      <String>[
        root,
        npmCache,
        npmPrefix,
        p.join(npmPrefix, 'lib'),
        uvCache,
        pipCache,
        bunInstall,
        denoDir,
        pnpmStore,
        yarnCache,
      ].map(
        (path) => Directory(
          path,
        ).create(recursive: true).timeout(mcpStdioFileOperationTimeout),
      ),
    );
    final environment = <String, String>{
      'npm_config_cache': npmCache,
      'npm_config_prefix': npmPrefix,
      'npm_config_yes': 'true',
      'PNPM_HOME': pnpmStore,
      'YARN_CACHE_FOLDER': yarnCache,
      'BUN_INSTALL': bunInstall,
      'DENO_DIR': denoDir,
      'UV_CACHE_DIR': uvCache,
      'PIP_CACHE_DIR': pipCache,
    };
    if (shouldInjectMcpChinaMirror()) {
      environment['npm_config_registry'] = mcpNpmMirrorRegistry;
      environment['UV_DEFAULT_INDEX'] = mcpPypiMirrorIndex;
      environment['PIP_INDEX_URL'] = mcpPypiMirrorIndex;
    }
    return environment;
  } catch (error, stack) {
    silentLog('mcp.stdio', 'isolatedPackageCacheEnv', error, stack);
    return const <String, String>{};
  }
}
