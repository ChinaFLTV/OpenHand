import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/mcp_bridge/mcp_loaded_tools_tracker.dart';

void main() {
  test('absorb only reports newly loaded ToolSearch names', () {
    final tracker = McpLoadedToolsTracker();
    addTearDown(tracker.dispose);

    final first = tracker.absorb(
      sessionId: 'session-a',
      loadedNamesRaw: <String>['mcp__browser__navigate'],
      totalDeferredRaw: 3,
      queryRaw: 'browser',
    );

    expect(first, <String>['mcp__browser__navigate']);
    expect(tracker.namesForSession('session-a'), <String>[
      'mcp__browser__navigate',
    ]);
    expect(tracker.historyForSession('session-a'), hasLength(1));

    final duplicate = tracker.absorb(
      sessionId: 'session-a',
      loadedNamesRaw: <String>['mcp__browser__navigate'],
      totalDeferredRaw: 3,
      queryRaw: 'browser',
    );

    expect(duplicate, isEmpty);
    expect(tracker.namesForSession('session-a'), <String>[
      'mcp__browser__navigate',
    ]);
    expect(tracker.historyForSession('session-a'), hasLength(1));
  });
}
