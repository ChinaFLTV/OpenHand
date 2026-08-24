import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/argument_guards.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../mcp_errors.dart';
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
    serverName: '${j['s'] ?? ''}',
    toolId: '${j['i'] ?? ''}',
    toolName: '${j['n'] ?? ''}',
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
        final out = <String, List<McpToolRef>>{};
        for (final entry in stringKeyedMapFromValue(raw).entries) {
          out[entry.key] = stringKeyedMapListFromValue(
            entry.value,
          ).map(McpToolRef.fromJson).toList(growable: false);
        }
        return out;
      }

      final builtAt = dateTimeFromValue(j['builtAt']);
      return McpKeywordIndex(
        byName: load(j['byName']),
        byDescription: load(j['byDescription']),
        bySearchHint: load(j['bySearchHint']),
        totalTools: nonNegativeIntFromValue(j['totalTools'], fallback: 0),
        totalServers: nonNegativeIntFromValue(j['totalServers'], fallback: 0),
        builtAt: builtAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        durationMs: nonNegativeIntFromValue(j['durationMs'], fallback: 0),
      );
    } catch (e, s) {
      silentLog('mcp_keyword_index', '从 JSON 解析关键词索引', e, s);
      return null;
    }
  }

  McpKeywordIndex replaceServerTools({
    required String serverName,
    required List<McpTool> tools,
  }) {
    final normalizedServerName = serverName.trim();
    if (normalizedServerName.isEmpty) return this;

    Map<String, List<McpToolRef>> withoutServer(
      Map<String, List<McpToolRef>> source,
    ) {
      final result = <String, List<McpToolRef>>{};
      for (final entry in source.entries) {
        final retained = entry.value
            .where((ref) => ref.serverName != normalizedServerName)
            .toList(growable: true);
        if (retained.isNotEmpty) result[entry.key] = retained;
      }
      return result;
    }

    final nextByName = withoutServer(byName);
    final nextByDescription = withoutServer(byDescription);
    final nextBySearchHint = withoutServer(bySearchHint);
    void ingest(
      Map<String, List<McpToolRef>> bucket,
      Set<String> tokens,
      McpToolRef ref,
    ) {
      for (final token in tokens) {
        bucket.putIfAbsent(token, () => <McpToolRef>[]).add(ref);
      }
    }

    for (final tool in tools) {
      final ref = McpToolRef(
        serverName: normalizedServerName,
        toolId: tool.id,
        toolName: tool.name,
      );
      ingest(nextByName, tokenizeForMcpKeywordIndex(tool.name), ref);
      ingest(
        nextByDescription,
        tokenizeForMcpKeywordIndex(tool.description),
        ref,
      );
      final hint = _mcpToolSearchHint(tool);
      if (hint != null) {
        ingest(nextBySearchHint, tokenizeForMcpKeywordIndex(hint), ref);
      }
    }

    final indexedTools = _collectIndexedTools(
      nextByName,
      nextByDescription,
      nextBySearchHint,
    );
    return McpKeywordIndex(
      byName: nextByName,
      byDescription: nextByDescription,
      bySearchHint: nextBySearchHint,
      totalTools: indexedTools.length,
      totalServers: indexedTools.map((ref) => ref.serverName).toSet().length,
      builtAt: DateTime.now().toUtc(),
      durationMs: 0,
    );
  }
}

/// 统计口径必须与全量构建一致：取三张倒排表的并集。
///
/// 只数 byName 会漏掉「工具名分词后为空（纯符号 / 全停用词），仅靠描述或
/// searchHint 入索引」的工具——这类服务一旦触发增量刷新，索引摘要里的
/// 服务数与工具数就会比全量构建凭空缩水。
Set<McpToolRef> _collectIndexedTools(
  Map<String, List<McpToolRef>> byName,
  Map<String, List<McpToolRef>> byDescription,
  Map<String, List<McpToolRef>> bySearchHint,
) {
  return <McpToolRef>{
    for (final refs in byName.values) ...refs,
    for (final refs in byDescription.values) ...refs,
    for (final refs in bySearchHint.values) ...refs,
  };
}

String? _mcpToolSearchHint(McpTool tool) {
  Object? raw = tool.annotations['searchHint'];
  raw ??= tool.annotations['search_hint'];
  raw ??= tool.rawMetadata['searchHint'];
  raw ??= tool.rawMetadata['search_hint'];
  if (raw == null) return null;
  if (raw is String) return nullIfBlank(raw);
  if (raw is List) {
    final joined = trimmedNonEmptyStrings(raw.whereType<String>()).join(' ');
    return joined.isEmpty ? null : joined;
  }
  return null;
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
/// 用于解耦索引构建与具体的工具发现实现。
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
  McpKeywordIndexService({
    Directory? storageDir,
    int maxPersistedBytes = _defaultMaxPersistedBytes,
  }) : _storageDir =
           storageDir ?? Directory(OpenHandPaths.defaultMcpDirectoryPath()),
       _maxPersistedBytes = maxPersistedBytes {
    requirePositiveIntAtMost(
      maxPersistedBytes,
      _maxAllowedPersistedBytes,
      'maxPersistedBytes',
    );
  }

  final Directory _storageDir;
  final int _maxPersistedBytes;
  final SerialTaskQueue _persistenceQueue = SerialTaskQueue();
  final OpenHandSingleFlight<McpKeywordIndexBuildResult> _buildFlight =
      OpenHandSingleFlight<McpKeywordIndexBuildResult>();
  bool _storageRecovered = false;
  int _persistenceRevision = 0;

  /// 整表重建进行期间发生的单服务替换，按 serverName 记最新一次的工具列表。
  /// 重建落盘时把它们叠加到全量结果上，避免二者互相覆盖（见 build 落盘处）。
  final Map<String, List<McpTool>> _replacesDuringBuild =
      <String, List<McpTool>>{};

  static const String _fileName = 'keyword_index.json';
  static const int _defaultMaxPersistedBytes = 32 * kBytesPerMiB;
  static const int _maxAllowedPersistedBytes = 256 * kBytesPerMiB;

  File get _file => File(p.join(_storageDir.path, _fileName));

  /// 单飞：同一时刻只允许一次构建。第二个 caller 会拿到第一个的 Future，
  /// 从而天然防止按钮抖动重复触发。
  Future<McpKeywordIndexBuildResult> build({
    required List<McpServer> servers,
    required McpServerToolsResolver resolveTools,
    required void Function(McpKeywordIndexProgress) onProgress,
    McpKeywordIndex? baseIndex,
  }) {
    return _buildFlight.run(() {
      final persistenceRevision = _persistenceRevision;
      // 本次重建的基线由此刻起算：清掉上一轮遗留的替换记录，只累积重建期间新到的。
      _replacesDuringBuild.clear();
      return _doBuild(
        servers: servers,
        resolveTools: resolveTools,
        onProgress: onProgress,
        persistenceRevision: persistenceRevision,
        baseIndex: baseIndex,
      );
    });
  }

  /// 当前是否有正在进行中的构建。
  bool get isBuilding => _buildFlight.isRunning;

  Future<McpKeywordIndexBuildResult> _doBuild({
    required List<McpServer> servers,
    required McpServerToolsResolver resolveTools,
    required void Function(McpKeywordIndexProgress) onProgress,
    required int persistenceRevision,
    required McpKeywordIndex? baseIndex,
  }) async {
    final stopwatch = Stopwatch()..start();
    final eligible = servers.where((s) => s.enabled).toList(growable: false);
    final eligibleNames = eligible.map((server) => server.name).toSet();
    final byName = <String, List<McpToolRef>>{};
    final byDescription = <String, List<McpToolRef>>{};
    final bySearchHint = <String, List<McpToolRef>>{};
    final dedupName = <String, Set<McpToolRef>>{};
    final dedupDesc = <String, Set<McpToolRef>>{};
    final dedupHint = <String, Set<McpToolRef>>{};
    void seed(
      Map<String, List<McpToolRef>> source,
      Map<String, List<McpToolRef>> bucket,
      Map<String, Set<McpToolRef>> dedup,
    ) {
      for (final entry in source.entries) {
        final retained = entry.value
            .where((ref) => eligibleNames.contains(ref.serverName))
            .toSet();
        if (retained.isEmpty) continue;
        dedup[entry.key] = retained;
        bucket[entry.key] = retained.toList(growable: true);
      }
    }

    if (baseIndex != null) {
      seed(baseIndex.byName, byName, dedupName);
      seed(baseIndex.byDescription, byDescription, dedupDesc);
      seed(baseIndex.bySearchHint, bySearchHint, dedupHint);
    }
    final errors = <String>[];
    var skipped = 0;
    var total = 0;
    for (var i = 0; i < eligible.length; i++) {
      final server = eligible[i];
      List<McpTool> tools;
      try {
        tools = await resolveTools(server);
      } catch (e, s) {
        silentLog('mcp_keyword_index', '解析服务工具（${server.name}）', e, s);
        errors.add(
          '${server.name}: ${mcpFailureMessage(e, fallback: '工具索引构建失败。')}',
        );
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
      if (tools.isEmpty) {
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
      _removeServerRefs(byName, dedupName, server.name);
      _removeServerRefs(byDescription, dedupDesc, server.name);
      _removeServerRefs(bySearchHint, dedupHint, server.name);
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
        final hint = _mcpToolSearchHint(tool);
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
      // 服务间主动让出事件循环，避免大型工具目录阻塞进度弹窗。
      await Future<void>.delayed(Duration.zero);
    }
    stopwatch.stop();
    final indexedTools = _collectIndexedTools(
      byName,
      byDescription,
      bySearchHint,
    );
    final index = McpKeywordIndex(
      byName: byName,
      byDescription: byDescription,
      bySearchHint: bySearchHint,
      totalTools: indexedTools.length,
      totalServers: indexedTools.map((ref) => ref.serverName).toSet().length,
      // 与空索引哨兵（isUtc: true）和 toJson 的 ISO8601 持久化保持一致。
      builtAt: DateTime.now().toUtc(),
      durationMs: stopwatch.elapsedMilliseconds,
    );
    final persistedIndex = await _persistenceQueue.enqueue(() async {
      // 全量重建始终落盘，不因期间发生过单服务替换而整轮丢弃（此前的守卫
      // 恰好反了：跳过重建、却让「陈旧全量 + 单服务增量」的替换写入胜出）。
      // 期间到达的替换比重建更新，叠加到全量结果之上，二者都不丢。
      var toPersist = index;
      if (persistenceRevision != _persistenceRevision &&
          _replacesDuringBuild.isNotEmpty) {
        for (final entry in _replacesDuringBuild.entries) {
          toPersist = toPersist.replaceServerTools(
            serverName: entry.key,
            tools: entry.value,
          );
        }
      }
      _replacesDuringBuild.clear();
      await _persist(toPersist);
      return toPersist;
    });
    return McpKeywordIndexBuildResult(
      index: persistedIndex,
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

  void _removeServerRefs(
    Map<String, List<McpToolRef>> bucket,
    Map<String, Set<McpToolRef>> dedup,
    String serverName,
  ) {
    for (final token in bucket.keys.toList(growable: false)) {
      bucket[token]!.removeWhere((ref) => ref.serverName == serverName);
      dedup[token]?.removeWhere((ref) => ref.serverName == serverName);
      if (bucket[token]!.isEmpty) {
        bucket.remove(token);
        dedup.remove(token);
      }
    }
  }

  Future<void> _persist(McpKeywordIndex index) async {
    final content = jsonEncode(index.toJson());
    if (utf8.encode(content).length + 1 > _maxPersistedBytes) {
      throw StateError('MCP 关键词索引超过持久化大小上限。');
    }
    await writeFileAtomically(_file, '$content\n');
  }

  Future<void> replacePersistedServerTools({
    required String serverName,
    required List<McpTool> tools,
  }) {
    _persistenceRevision += 1;
    // 若此刻有整表重建在途，记下这次替换：重建落盘时会把它叠加到全量结果上。
    // 二者都仍各自落盘，且重建的 persist 一定排在本任务之后，故无论调度次序如何，
    // 最终盘面都是「全量 + 本次替换」；即便重建中途失败，本任务也已把增量写盘。
    if (_buildFlight.isRunning) {
      _replacesDuringBuild[serverName] = tools;
    }
    return _persistenceQueue.enqueue(() async {
      final current = await _loadFromDisk();
      if (current == null) return;
      await _persist(
        current.replaceServerTools(serverName: serverName, tools: tools),
      );
    });
  }

  /// 启动期惰性加载已落盘的索引。文件不存在 / 解析失败时返回 null。
  Future<McpKeywordIndex?> loadFromDisk() {
    return _persistenceQueue.enqueue(_loadFromDisk);
  }

  Future<void> flush() async {
    try {
      await _buildFlight.idle;
    } finally {
      await _persistenceQueue.idle;
    }
  }

  Future<McpKeywordIndex?> _loadFromDisk() async {
    try {
      if (!_storageRecovered) {
        await recoverAtomicWriteBackupIfNeeded(_file);
        _storageRecovered = true;
      }
      if (!await regularFileExistsBounded(_file)) return null;
      final raw = await readBoundedFileString(
        _file,
        maxBytes: _maxPersistedBytes,
      );
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return McpKeywordIndex.fromJson(stringKeyedMapFromValue(decoded));
    } catch (e, s) {
      silentLog('mcp_keyword_index', '从磁盘加载关键词索引', e, s);
      return null;
    }
  }
}
