import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/features/services/widgets/dependency_metric_detail_dialog.dart';
import 'package:provider/provider.dart';

void main() {
  final sizes = <String, Size>{
    '桌面': const Size(1200, 900),
    '移动': const Size(390, 844),
  };

  for (final size in sizes.entries) {
    testWidgets('${size.key}尺寸可打开全部指标详情且无布局异常', (tester) async {
      await tester.binding.setSurfaceSize(size.value);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ServicesController();
      addTearDown(controller.dispose);
      final base = DateTime(2026, 8, 4, 12);
      for (var index = 0; index < 3; index++) {
        controller.debugSetDependencyDataOverview(
          _overview(base.add(Duration(seconds: index * 8)), index),
        );
      }

      DependencyMetricKind selected = DependencyMetricKind.postgresqlCapacity;
      await tester.pumpWidget(
        ChangeNotifierProvider<ServicesController>.value(
          value: controller,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showDependencyMetricDetailDialog(
                    context,
                    kind: selected,
                    postgresqlTables: _tables,
                    redisRecords: _records,
                    onReload: () async {},
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );

      for (final kind in DependencyMetricKind.values) {
        selected = kind;
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        expect(find.text(_kindTitle(kind)), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.close_rounded).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}

String _kindTitle(DependencyMetricKind kind) => switch (kind) {
  DependencyMetricKind.postgresqlCapacity => 'PostgreSQL 数据库容量',
  DependencyMetricKind.postgresqlConnections => 'PostgreSQL 活跃连接',
  DependencyMetricKind.postgresqlCache => 'PostgreSQL 缓存命中率',
  DependencyMetricKind.postgresqlTransactions => 'PostgreSQL 事务提交',
  DependencyMetricKind.redisMemory => 'Redis 内存占用',
  DependencyMetricKind.redisKeyspace => 'Redis 键空间',
  DependencyMetricKind.redisThroughput => 'Redis 实时吞吐',
  DependencyMetricKind.redisCache => 'Redis 缓存命中率',
  DependencyMetricKind.redisClients => 'Redis 客户端',
  DependencyMetricKind.redisNetwork => 'Redis 网络流量',
};

Map<String, Object?> _overview(
  DateTime capturedAt,
  int step,
) => <String, Object?>{
  'capturedAt': capturedAt.toIso8601String(),
  'postgresql': <String, Object?>{
    'poolSize': 8,
    'idleConnections': 5 - step,
    'tables': _tables,
    'telemetry': <String, Object?>{
      'serverVersion': '17.5',
      'databaseSizeBytes': 80 * 1024 * 1024 + step * 1024 * 1024,
      'tableDataBytes': 48 * 1024 * 1024,
      'indexBytes': 20 * 1024 * 1024,
      'toastBytes': 2 * 1024 * 1024,
      'temporaryBytes': 1024 * 1024,
      'tablespaceCapacityBytes': 1024 * 1024 * 1024,
      'activeConnections': 3 + step,
      'maxConnections': 100,
      'connectionStates': <String, Object?>{'等待': 1, '阻塞': 1, '事务中空闲': 2},
      'connectionsByApplication': <String, Object?>{'OpenHand': 6, '维护任务': 2},
      'sessions': <Object?>[
        <String, Object?>{
          'pid': 101,
          'user': 'openhand',
          'application': 'worker',
          'state': 'active',
          'waitEvent': 'Lock',
          'durationSeconds': 320,
          'blocked': true,
        },
      ],
      'blocksHit': 10000 + step * 100,
      'blocksRead': 120 + step * 2,
      'indexBlocksHit': 8000 + step * 80,
      'indexBlocksRead': 90 + step,
      'sharedBuffersBytes': 128 * 1024 * 1024,
      'sharedBuffersUsedBytes': 96 * 1024 * 1024,
      'lowCacheObjects': <Object?>[
        <String, Object?>{
          'name': 'hunt_results',
          'type': '表',
          'hitRate': 0.82,
          'blocksRead': 80,
        },
      ],
      'transactionsCommitted': 2000 + step * 40,
      'transactionsRolledBack': 20 + step,
      'deadlocks': step,
      'conflicts': 2,
      'transactionDurationBuckets': <String, Object?>{
        '< 10 ms': 18,
        '10 - 100 ms': 8,
        '> 1 s': 1,
      },
      'transactionExceptions': <Object?>[
        <String, Object?>{
          'occurredAt': capturedAt.toIso8601String(),
          'type': '回滚',
          'session': 'worker-2',
          'durationMs': 1400,
          'reason': '锁等待超时',
        },
      ],
    },
  },
  'redis': <String, Object?>{
    'usedMemoryBytes': 48 * 1024 * 1024 + step * 512 * 1024,
    'usedMemoryRssBytes': 62 * 1024 * 1024,
    'peakMemoryBytes': 72 * 1024 * 1024,
    'datasetMemoryBytes': 40 * 1024 * 1024,
    'overheadMemoryBytes': 8 * 1024 * 1024,
    'maxMemoryBytes': 256 * 1024 * 1024,
    'memoryFragmentationRatio': 1.29,
    'keyCount': 1200 + step * 5,
    'expiredKeys': 80 + step,
    'evictedKeys': 2,
    'keyspaces': <Object?>[
      <String, Object?>{
        'database': 'db0',
        'keys': 1200,
        'expires': 720,
        'averageTtlMs': 3600000,
      },
    ],
    'operationsPerSecond': 240 + step * 30,
    'totalCommands': 10000 + step * 2000,
    'commandCategories': <String, Object?>{'读取': 7000, '写入': 2500, '管理': 500},
    'averageCommandLatencyMs': 0.8,
    'p95CommandLatencyMs': 2.4,
    'p99CommandLatencyMs': 8.2,
    'commandStats': <Object?>[
      <String, Object?>{
        'command': 'get',
        'calls': 7000,
        'microsecondsPerCall': 1.2,
        'microseconds': 8400,
      },
    ],
    'slowCommands': <Object?>[
      <String, Object?>{
        'occurredAt': capturedAt.toIso8601String(),
        'command': 'HGETALL openhand:cache',
        'durationMs': 14.2,
        'client': '127.0.0.1:52000',
      },
    ],
    'keyspaceHits': 9000 + step * 900,
    'keyspaceMisses': 500 + step * 50,
    'cacheHitDimensions': <Object?>[
      <String, Object?>{
        'name': 'HGET',
        'requests': 900,
        'hitRate': 0.74,
        'misses': 234,
      },
    ],
    'connectedClients': 12 + step,
    'blockedClients': 1,
    'maxClients': 10000,
    'rejectedConnections': 2,
    'clients': <Object?>[
      <String, Object?>{
        'address': '127.0.0.1:52000',
        'name': 'worker',
        'application': 'OpenHand',
        'database': 0,
        'subscriptions': 0,
        'lastCommand': 'hgetall',
        'idleSeconds': 1800,
        'ageSeconds': 7200,
        'commands': 18000,
      },
    ],
    'networkInputBytes': 8 * 1024 * 1024 + step * 320 * 1024,
    'networkOutputBytes': 25 * 1024 * 1024 + step * 960 * 1024,
    'networkSources': <Object?>[
      <String, Object?>{
        'client': 'worker',
        'inputBytes': 3 * 1024 * 1024,
        'outputBytes': 12 * 1024 * 1024,
      },
    ],
  },
};

const List<Map<String, Object?>> _tables = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'hunt_results',
    'rowCount': 1200,
    'totalBytes': 34 * 1024 * 1024,
    'dataBytes': 22 * 1024 * 1024,
    'indexBytes': 10 * 1024 * 1024,
  },
  <String, Object?>{
    'name': 'hunt_jobs',
    'rowCount': 120,
    'totalBytes': 12 * 1024 * 1024,
    'dataBytes': 8 * 1024 * 1024,
    'indexBytes': 3 * 1024 * 1024,
  },
];

const List<Map<String, Object?>> _records = <Map<String, Object?>>[
  <String, Object?>{
    'key': 'openhand:cache:results',
    'type': 'hash',
    'sizeBytes': 3 * 1024 * 1024,
    'ttlSeconds': 1800,
  },
  <String, Object?>{
    'key': 'openhand:queue:pending',
    'type': 'list',
    'sizeBytes': 420 * 1024,
    'ttlSeconds': -1,
  },
];
