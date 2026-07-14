import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';

/// stdio MCP 隔离包缓存根目录：~/.openhand/mcp/package-cache。
String mcpStdioIsolatedCacheRoot() =>
    p.join(OpenHandPaths.defaultMcpDirectoryPath(), 'package-cache');
