import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/model/mcp_server_ops.dart';
import 'package:openhand/features/mcp/service/mcp_server_ops_runtime.dart';

void main() {
  test('concurrent lifecycle requests execute in submission order', () async {
    final states = <McpOpsLifecycleState>[];
    final runtime = McpServerOpsRuntime(
      toolListProvider: () => const <McpOpsToolDefinition>[],
      toolInvoker: (_, _, _) async =>
          throw UnsupportedError('No tool invocation is expected.'),
      approvalGate: (_) async => true,
      auditSink: (_) {},
      snapshotSink: (snapshot) => states.add(snapshot.lifecycle),
    );
    const config = McpOpsConfig(listenPort: 0);

    await Future.wait<void>(<Future<void>>[
      runtime.start(config),
      runtime.restart(config),
      runtime.stop(),
    ]);

    expect(runtime.isRunning, isFalse);
    expect(runtime.snapshot.lifecycle, McpOpsLifecycleState.stopped);
    expect(states, <McpOpsLifecycleState>[
      McpOpsLifecycleState.starting,
      McpOpsLifecycleState.running,
      McpOpsLifecycleState.restarting,
      McpOpsLifecycleState.stopping,
      McpOpsLifecycleState.stopped,
      McpOpsLifecycleState.starting,
      McpOpsLifecycleState.running,
      McpOpsLifecycleState.stopping,
      McpOpsLifecycleState.stopped,
    ]);
  });
}
