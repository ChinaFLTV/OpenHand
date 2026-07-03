import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/mcp_bridge/mcp_loaded_tools_tracker.dart';

void main() {
  test('ToolSearch loaded names are trimmed, deduped, and sorted', () {
    final tracker = McpLoadedToolsTracker();
    addTearDown(tracker.dispose);

    final firstAdded = tracker.absorb(
      sessionId: 'session-1',
      loadedNamesRaw: const <Object?>[
        '  BetaTool ',
        'AlphaTool',
        'AlphaTool ',
        '',
        42,
      ],
      totalDeferredRaw: -1,
      queryRaw: '  select:BetaTool,AlphaTool ',
    );

    expect(firstAdded, <String>['AlphaTool', 'BetaTool']);
    expect(tracker.namesForSession('session-1'), <String>[
      'AlphaTool',
      'BetaTool',
    ]);
    expect(tracker.rawSetForSession('session-1').toList(), <String>[
      'AlphaTool',
      'BetaTool',
    ]);
    expect(tracker.signal.value?.loadedNames, <String>[
      'AlphaTool',
      'BetaTool',
    ]);
    expect(tracker.signal.value?.totalDeferred, 2);
    expect(tracker.signal.value?.query, 'select:BetaTool,AlphaTool');

    final secondAdded = tracker.absorb(
      sessionId: 'session-1',
      loadedNamesRaw: const <Object?>['GammaTool', ' BetaTool'],
      totalDeferredRaw: 3.8,
      queryRaw: 'gamma',
    );

    expect(secondAdded, <String>['GammaTool']);
    expect(tracker.namesForSession('session-1'), <String>[
      'AlphaTool',
      'BetaTool',
      'GammaTool',
    ]);
    final history = tracker.historyForSession('session-1');
    expect(history, hasLength(2));
    expect(history.first.addedNames, <String>['AlphaTool', 'BetaTool']);
    expect(history.last.addedNames, <String>['GammaTool']);
    expect(history.last.totalDeferred, 3);
  });
}
