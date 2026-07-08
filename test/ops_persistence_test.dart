import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/data/mcp_server_ops_store.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server_ops.dart';
import 'package:openhand/features/message_gateway/data/web_gateway_ops_store.dart';
import 'package:openhand/features/message_gateway/model/web_gateway_runtime.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'MCP ops config, metrics and audit logs survive controller cold load',
    () async {
      final dir = await Directory.systemTemp.createTemp('openhand_mcp_ops_');
      try {
        final store = McpServerOpsStore(storageDirectoryPath: dir.path);
        const config = McpOpsConfig(
          autoStart: true,
          listenPort: 9876,
          rpmLimit: 321,
          writeMode: McpOpsWriteMode.fullAccess,
        );
        await store.saveConfig(config);
        await store.saveRuntimeData(
          McpOpsPersistedRuntimeData(
            snapshot: McpOpsRuntimeSnapshot(
              requestTotal: 9,
              blockedTotal: 2,
              failedTotal: 1,
              inboundBytes: 1024,
              outboundBytes: 2048,
              trafficSeries: <McpOpsTrafficSample>[
                McpOpsTrafficSample(
                  minute: DateTime.utc(2026, 7, 8, 10, 30),
                  success: 6,
                  blocked: 2,
                  failed: 1,
                  avgLatencyMs: 12,
                  p95LatencyMs: 30,
                ),
              ],
            ),
            auditEntries: <McpOpsAuditEntry>[
              McpOpsAuditEntry(
                id: 'audit-1',
                timestamp: DateTime.utc(2026, 7, 8, 10, 31),
                toolName: 'builtin.Read',
                surface: 'builtin_tools',
                endpoint: 'invoke',
                status: 'success',
                protocol: 'mcp',
                model: 'local',
                clientName: 'test-client',
                ipAddress: '127.0.0.1',
                durationMs: 18,
                promptTokens: 3,
                completionTokens: 5,
                inboundBytes: 128,
                outboundBytes: 256,
              ),
            ],
          ),
        );

        final controller = McpController.uninitialized(
          initialFilePath: p.join(dir.path, 'mcp_servers.json'),
        );
        try {
          await controller.ensureOpsPersistenceLoaded();

          expect(controller.opsConfig.listenPort, 9876);
          expect(controller.opsConfig.rpmLimit, 321);
          expect(controller.opsConfig.writeMode, McpOpsWriteMode.fullAccess);
          expect(controller.opsSnapshot.requestTotal, 9);
          expect(controller.opsSnapshot.successTotal, 6);
          expect(controller.opsSnapshot.inboundBytes, 1024);
          expect(controller.opsSnapshot.trafficSeries, hasLength(1));
          expect(controller.opsAuditEntries.map((entry) => entry.id), [
            'audit-1',
          ]);
        } finally {
          controller.dispose();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'Web gateway ops store round-trips snapshots, logs and cleanup history',
    () async {
      final dir = await Directory.systemTemp.createTemp('openhand_web_ops_');
      try {
        final store = WebGatewayOpsStore(
          filePath: p.join(dir.path, 'web_gateway_ops_history.json'),
        );
        final cleanup = WebGatewayCleanupResult(
          timestamp: DateTime.utc(2026, 7, 8, 10, 32),
          target: 'logs',
          expiredOnly: false,
          deletedFiles: 2,
          deletedDirectories: 1,
          bytesFreed: 4096,
          memoryLogEntriesCleared: 7,
        );
        final snapshot = WebGatewayRuntimeSnapshot(
          state: WebGatewayRuntimeState.running,
          startedAt: DateTime.utc(2026, 7, 8, 10),
          uptimeMs: 120000,
          boundUrl: 'http://127.0.0.1:8848',
          accessibleUrls: const <String>['http://127.0.0.1:8848'],
          activeRequests: 1,
          maxConcurrentRequests: 200,
          activeRequestRatio: 0.005,
          totalRequests: 42,
          totalErrors: 3,
          totalBytesIn: 8192,
          totalBytesOut: 16384,
          crashCount: 0,
          restartCount: 1,
          currentRssBytes: 1024,
          maxRssBytes: 2048,
          cpuPercent: 3.5,
          threadCount: 8,
          fileHandleCount: 64,
          swapBytes: 0,
          logBytes: 512,
          openSessionCount: 2,
          lastError: 'last-error',
          statusCodeBreakdown: const <String, int>{'2xx': 39, '5xx': 3},
          methodBreakdown: const <String, int>{'POST': 42},
          latencyStats: const WebGatewayLatencyStats(
            sampleCount: 3,
            avgMs: 10,
            p50Ms: 8,
            p95Ms: 20,
            p99Ms: 24,
            maxMs: 25,
          ),
          memoryLogCount: 1,
        );
        final log = WebGatewayLogEntry(
          id: 7,
          timestamp: DateTime.utc(2026, 7, 8, 10, 33),
          level: WebGatewayLogLevel.warn,
          tag: 'OPS',
          message: 'persist me',
        );

        await store.save(
          WebGatewayOpsHistoryData(
            snapshots: <WebGatewayOpsSnapshotRecord>[
              WebGatewayOpsSnapshotRecord(
                timestamp: DateTime.utc(2026, 7, 8, 10, 34),
                snapshot: snapshot,
              ),
            ],
            logs: <WebGatewayLogEntry>[log],
            cleanupHistory: <WebGatewayCleanupResult>[cleanup],
          ),
        );

        final loaded = await WebGatewayOpsStore(
          filePath: store.filePath,
        ).load();

        expect(loaded.snapshots.single.snapshot.totalRequests, 42);
        expect(loaded.snapshots.single.snapshot.latencyStats.p95Ms, 20);
        expect(loaded.logs.single.message, 'persist me');
        expect(loaded.cleanupHistory.single.bytesFreed, 4096);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
