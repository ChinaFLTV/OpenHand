import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../model/mcp_server.dart';
import '../model/mcp_tool.dart';
import 'mcp_keyword_tokenizer.dart';

/// 单条工具的反查引用（落在倒排桶里的值）。
class McpToolRef {
  const McpToolRef({
    required this.serverName,
    required this.toolId,
    required this.toolName,
  });

  final String serverName;
  final String toolId;
  final String toolName;

  Map<String, Object?> toJson() => <String, Object?>{
    's': serverName,
    'i': toolId,
    'n': toolName,
  };

  static McpToolRef fromJson(Map<String, Object?> j) => McpToolRef(
    serverName: (j['s'] as String?) ?? '',
    toolId: (j['i'] as String?) ?? '',
    toolName: (j['n'] as String?) ?? '',
  );

  @override
  int get hashCode => Object.hash(serverName, toolId);

  @override
  bool operator ==(Object other) =>
      other is McpToolRef &&
      other.serverName == serverName &&
      other.toolId == toolId;
}

/// 三个倒排桶 + 元信息。
class McpKeywordIndex {
  const McpKeywordIndex({
    required this.byName,
    required this.byDescription,
    required this.bySearchHint,
    required this.totalTools,
    required this.totalServers,
    required this.builtAt,
    required this.durationMs,
  });

  final Map<String, List<McpToolRef>> byName;
  final Map<String, List<McpToolRef>> byDescription;
  final Map<String, List<McpToolRef>> bySearchHint;
  final int totalTools;
  final int totalServers;
  final DateTime builtAt;
  final int durationMs;

  static final McpKeywordIndex empty = McpKeywordIndex(
    byName: const <String, List<McpToolRef>>{},
    byDescription: const <String, List<McpToolRef>>{},
    bySearchHint: const <String, List<McpToolRef>>{},
    totalTools: 0,
    totalServers: 0,
    builtAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    durationMs: 0,
  );

  Map<String, Object?> toJson() {
    Map<String, List<Map<String, Object?>>> dump(
      Map<String, List<McpToolRef>> m,
    ) {
      final out = <String, List<Map<String, Object?>>>{};
      m.forEach((k, v) {
        out[k] = v.map((e) => e.toJson()).toList(growable: false);
      });
      return out;
    }

    return <String, Object?>{
      'version': 1,
      'totalTools': totalTools,
      'totalServers': totalServers,
      'builtAt': builtAt.toIso8601String(),
      'durationMs': durationMs,
      'byName': dump(byName),
      'byDescription': dump(byDescription),
      'bySearchHint': dump(bySearchHint),
    };
  }

  static McpKeywordIndex? fromJson(Map<String, Object?> j) {
    try {
      Map<String, List<McpToolRef>> load(Object? raw) {
        if (raw is! Map) return <String, List<McpToolRef>>{};
        final out = <String, List<McpToolRef>>{};
        raw.forEach((k, v) {
          if (k is! String || v is! List) return;
          out[k] = v
              .whereType<Map>()
              .map((e) => McpToolRef.fromJson(Map<String, Object?>.from(e)))
              .toList(growable: false);
        });
        return out;
      }

      final builtAt = DateTime.tryParse((j['builtAt'] as String?) ?? '');
      return McpKeywordIndex(
        byName: load(j['byName']),
        byDescription: load(j['byDescription']),
        bySearchHint: load(j['bySearchHint']),
        totalTools: (j['totalTools'] as int?) ?? 0,
        totalServers: (j['totalServers'] as int?) ?? 0,
        builtAt: builtAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        durationMs: (j['durationMs'] as int?) ?? 0,
      );
    } catch (e, s) {
      silentLog('mcp_keyword_index', 'fromJson', e, s);
      return null;
    }
  }
}

/// 构建过程中向 UI 推送的进度事件。
class McpKeywordIndexProgress {
  const McpKeywordIndexProgress({
    required this.serverIndex,
    required this.serverCount,
    required this.serverName,
    required this.toolsScanned,
    required this.totalToolsScanned,
    required this.skipped,
  });

  final int serverIndex; // 1-based
  final int serverCount;
  final String serverName;
  final int toolsScanned; // 当前服务已扫工具数
  final int totalToolsScanned; // 全局累计扫描工具数
  final int skipped; // 跳过（无可用工具 / 服务禁用 / 异常）的服务数
}

class McpKeywordIndexBuildResult {
  const McpKeywordIndexBuildResult({
    required this.index,
    required this.skippedServers,
    required this.errors,
  });

  final McpKeywordIndex index;
  final int skippedServers;
  final List<String> errors;
}

/// 拉取每个 server 当前可用的 tool 列表的回调，由 [McpController] 注入，
/// 解耦索引构建与具体的发现实现，便于测试与 mocked discovery。
typedef McpServerToolsResolver =
    FutureOr<List<McpTool>> Function(McpServer server);

/// 关键词倒排索引构建 / 持久化服务。
///
/// 构建流程：
///   1. 遍历可用 server（disabled 的跳过），逐 server 拉工具
///   2. 对 name / description / annotations.searchHint || rawMetadata.searchHint
///      分别用 `tokenizeForMcpKeywordIndex` 切词，写入对应桶
///   3. 每完成一个 server 通过 `progress` Stream 上报，并 `await Future(() {})`
///      让出事件循环，避免 UI 卡顿
///   4. 构建结束后落盘 `~/.openhand/mcp/keyword_index.json`
///
/// 防抖：上层应自行节流（按钮上锁 / 单飞 Future）。
class McpKeywordIndexService {
  McpKeywordIndexService({Directory? storageDir})
    : _storageDir =
          storageDir ?? Directory(OpenHandPaths.defaultMcpDirectoryPath());

  final Directory _storageDir;
  Future<McpKeywordIndexBuildResult>? _inflight;

  static const String _fileName = 'keyword_index.json';

  File get _file => File(p.join(_storageDir.path, _fileName));

  /// 单飞：同一时刻只允许一次构建。第二个 caller 会拿到第一个的 Future，
  /// 从而天然防止按钮抖动重复触发。
  Future<McpKeywordIndexBuildResult> build({
    required List<McpServer> servers,
    required McpServerToolsResolver resolveTools,
    required void Function(McpKeywordIndexProgress) onProgress,
  }) {
    final existing = _inflight;
    if (existing != null) return existing;
    final fut = _doBuild(
      servers: servers,
      resolveTools: resolveTools,
      onProgress: onProgress,
    );
    _inflight = fut;
    fut.whenComplete(() {
      _inflight = null;
    });
    return fut;
  }

  /// 当前是否有正在进行中的构建。
  bool get isBuilding => _inflight != null;

  Future<McpKeywordIndexBuildResult> _doBuild({
    required List<McpServer> servers,
    required McpServerToolsResolver resolveTools,
    required void Function(McpKeywordIndexProgress) onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final byName = <String, List<McpToolRef>>{};
    final byDescription = <String, List<McpToolRef>>{};
    final bySearchHint = <String, List<McpToolRef>>{};
    final dedupName = <String, Set<McpToolRef>>{};
    final dedupDesc = <String, Set<McpToolRef>>{};
    final dedupHint = <String, Set<McpToolRef>>{};
    final errors = <String>[];
    var skipped = 0;
    var total = 0;
    final eligible = servers.where((s) => s.enabled).toList(growable: false);
    for (var i = 0; i < eligible.length; i++) {
      final server = eligible[i];
      List<McpTool> tools;
      try {
        tools = await resolveTools(server);
      } catch (e, s) {
        silentLog('mcp_keyword_index', 'resolveTools(${server.name})', e, s);
        errors.add('${server.name}: $e');
        skipped++;
        onProgress(
          McpKeywordIndexProgress(
            serverIndex: i + 1,
            serverCount: eligible.length,
            serverName: server.name,
            toolsScanned: 0,
            totalToolsScanned: total,
            skipped: skipped,
          ),
        );
        continue;
      }
      var localScanned = 0;
      for (final tool in tools) {
        final ref = McpToolRef(
          serverName: server.name,
          toolId: tool.id,
          toolName: tool.name,
        );
        _ingest(dedupName, byName, tokenizeForMcpKeywordIndex(tool.name), ref);
        _ingest(
          dedupDesc,
          byDescription,
          tokenizeForMcpKeywordIndex(tool.description),
          ref,
        );
        final hint = _extractSearchHint(tool);
        if (hint != null) {
          _ingest(
            dedupHint,
            bySearchHint,
            tokenizeForMcpKeywordIndex(hint),
            ref,
          );
        }
        localScanned++;
        total++;
      }
      onProgress(
        McpKeywordIndexProgress(
          serverIndex: i + 1,
          serverCount: eligible.length,
          serverName: server.name,
          toolsScanned: localScanned,
          totalToolsScanned: total,
          skipped: skipped,
        ),
      );
      // Yield to UI between servers — keeps progress dialog smooth on
      // Catalogs with hundreds of tools (e.g. odin-cloud-ma).
      await Future<void>.delayed(Duration.zero);
    }
    stopwatch.stop();
    final index = McpKeywordIndex(
      byName: byName,
      byDescription: byDescription,
      bySearchHint: bySearchHint,
      totalTools: total,
      totalServers: eligible.length,
      builtAt: DateTime.now(),
      durationMs: stopwatch.elapsedMilliseconds,
    );
    unawaited(_persist(index));
    return McpKeywordIndexBuildResult(
      index: index,
      skippedServers: skipped,
      errors: errors,
    );
  }

  void _ingest(
    Map<String, Set<McpToolRef>> dedup,
    Map<String, List<McpToolRef>> bucket,
    Set<String> tokens,
    McpToolRef ref,
  ) {
    for (final tk in tokens) {
      final set = dedup.putIfAbsent(tk, () => <McpToolRef>{});
      if (set.add(ref)) {
        bucket.putIfAbsent(tk, () => <McpToolRef>[]).add(ref);
      }
    }
  }

  String? _extractSearchHint(McpTool tool) {
    Object? raw = tool.annotations['searchHint'];
    raw ??= tool.annotations['search_hint'];
    raw ??= tool.rawMetadata['searchHint'];
    raw ??= tool.rawMetadata['search_hint'];
    if (raw == null) return null;
    if (raw is String) return raw.trim().isEmpty ? null : raw;
    if (raw is List) {
      final joined = raw
          .whereType<String>()
          .where((e) => e.trim().isNotEmpty)
          .join(' ');
      return joined.isEmpty ? null : joined;
    }
    return null;
  }

  Future<void> _persist(McpKeywordIndex index) async {
    try {
      if (!await _storageDir.exists()) {
        await _storageDir.create(recursive: true);
      }
      // Atomic-ish: write to .tmp, rename. Avoids leaving a half-written
      // index if the process is killed mid-flush.
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(index.toJson()), flush: true);
      await tmp.rename(_file.path);
    } catch (e, s) {
      silentLog('mcp_keyword_index', 'persist', e, s);
    }
  }

  /// 启动期惰性加载已落盘的索引。文件不存在 / 解析失败时返回 null。
  Future<McpKeywordIndex?> loadFromDisk() async {
    try {
      if (!await _file.exists()) return null;
      final raw = await _file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return McpKeywordIndex.fromJson(Map<String, Object?>.from(decoded));
    } catch (e, s) {
      silentLog('mcp_keyword_index', 'loadFromDisk', e, s);
      return null;
    }
  }

  /// 删除落盘文件（设置项「关闭索引」时使用）。
  Future<void> deleteFromDisk() async {
    try {
      if (await _file.exists()) await _file.delete();
    } catch (e, s) {
      silentLog('mcp_keyword_index', 'deleteFromDisk', e, s);
    }
  }
}
