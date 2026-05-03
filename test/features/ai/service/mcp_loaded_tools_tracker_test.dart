import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/service/mcp_loaded_tools_tracker.dart';

void main() {
  group('McpLoadedToolsTracker', () {
    test('absorbs loaded names and broadcasts an event with revision 1', () {
      final tracker = McpLoadedToolsTracker();
      addTearDown(tracker.dispose);

      final added = tracker.absorb(
        sessionId: 'sess-A',
        loadedNamesRaw: <Object>['mcp__svr__alpha', 'mcp__svr__beta'],
        totalDeferredRaw: 5,
        queryRaw: 'alpha',
      );

      expect(added, <String>['mcp__svr__alpha', 'mcp__svr__beta']);
      final event = tracker.signal.value;
      expect(event, isNotNull);
      expect(event!.sessionId, 'sess-A');
      expect(event.loadedNames, <String>['mcp__svr__alpha', 'mcp__svr__beta']);
      expect(event.totalDeferred, 5);
      expect(event.query, 'alpha');
      expect(event.revision, 1);
      expect(event.loadedCount, 2);

      expect(tracker.namesForSession('sess-A'), <String>[
        'mcp__svr__alpha',
        'mcp__svr__beta',
      ]);
      expect(tracker.rawSetForSession('sess-A'), <String>{
        'mcp__svr__alpha',
        'mcp__svr__beta',
      });
    });

    test('absorb is no-op when payload is empty / wrong type', () {
      final tracker = McpLoadedToolsTracker();
      addTearDown(tracker.dispose);

      expect(tracker.absorb(sessionId: 'x', loadedNamesRaw: null), isEmpty);
      expect(tracker.absorb(sessionId: 'x', loadedNamesRaw: <String>[]), isEmpty);
      expect(tracker.absorb(sessionId: 'x', loadedNamesRaw: 'string'), isEmpty);
      expect(tracker.signal.value, isNull);
      expect(tracker.namesForSession('x'), isEmpty);
    });

    test('namesForSession returns sorted unmodifiable view', () {
      final tracker = McpLoadedToolsTracker();
      addTearDown(tracker.dispose);

      tracker.absorb(
        sessionId: 's',
        loadedNamesRaw: <String>['mcp__b', 'mcp__a', 'mcp__c'],
      );

      final names = tracker.namesForSession('s');
      expect(names, <String>['mcp__a', 'mcp__b', 'mcp__c']);
      expect(() => names.add('mcp__d'), throwsUnsupportedError);
    });

    test('revision increments per absorb so identical payloads still notify', () {
      final tracker = McpLoadedToolsTracker();
      addTearDown(tracker.dispose);

      tracker.absorb(
        sessionId: 's',
        loadedNamesRaw: <String>['mcp__a'],
      );
      final firstRevision = tracker.signal.value!.revision;

      tracker.absorb(
        sessionId: 's',
        loadedNamesRaw: <String>['mcp__a'],
      );
      final secondRevision = tracker.signal.value!.revision;

      expect(secondRevision, firstRevision + 1);
    });

    test('clearSession returns count and removes the session bucket', () {
      final tracker = McpLoadedToolsTracker();
      addTearDown(tracker.dispose);

      tracker.absorb(
        sessionId: 's',
        loadedNamesRaw: <String>['mcp__a', 'mcp__b'],
      );
      expect(tracker.namesForSession('s'), hasLength(2));

      final removed = tracker.clearSession('s');
      expect(removed, 2);
      expect(tracker.namesForSession('s'), isEmpty);
      expect(tracker.rawSetForSession('s'), isEmpty);

      // Clearing again is a safe no-op returning 0.
      expect(tracker.clearSession('s'), 0);
      expect(tracker.clearSession('never-existed'), 0);
    });

    test('per-session buckets are isolated', () {
      final tracker = McpLoadedToolsTracker();
      addTearDown(tracker.dispose);

      tracker.absorb(sessionId: 'A', loadedNamesRaw: <String>['mcp__alpha']);
      tracker.absorb(sessionId: 'B', loadedNamesRaw: <String>['mcp__bravo']);

      expect(tracker.namesForSession('A'), <String>['mcp__alpha']);
      expect(tracker.namesForSession('B'), <String>['mcp__bravo']);

      tracker.clearSession('A');
      expect(tracker.namesForSession('A'), isEmpty);
      expect(tracker.namesForSession('B'), <String>['mcp__bravo']);
    });

    test('totalDeferred falls back to addedNames length on missing/garbage', () {
      final tracker = McpLoadedToolsTracker();
      addTearDown(tracker.dispose);

      tracker.absorb(
        sessionId: 's',
        loadedNamesRaw: <String>['mcp__a', 'mcp__b'],
        totalDeferredRaw: 'not-a-number',
      );

      expect(tracker.signal.value!.totalDeferred, 2);
      expect(tracker.signal.value!.query, '');
    });

    test('history captures every absorb call in chronological order', () {
      final tracker = McpLoadedToolsTracker();
      addTearDown(tracker.dispose);

      tracker.absorb(
        sessionId: 'sess',
        loadedNamesRaw: <String>['mcp__alpha__one'],
        queryRaw: 'alpha',
        totalDeferredRaw: 10,
      );
      tracker.absorb(
        sessionId: 'sess',
        loadedNamesRaw: <String>['mcp__beta__two', 'mcp__beta__three'],
        queryRaw: 'beta',
        totalDeferredRaw: 9,
      );

      final history = tracker.historyForSession('sess');
      expect(history, hasLength(2));
      expect(history[0].query, 'alpha');
      expect(history[0].addedNames, ['mcp__alpha__one']);
      expect(history[0].totalDeferred, 10);
      expect(history[1].query, 'beta');
      expect(history[1].addedNames, ['mcp__beta__three', 'mcp__beta__two']);
      expect(history[1].totalDeferred, 9);
      // Returned list should be unmodifiable.
      expect(
        () => history.add(history.first),
        throwsUnsupportedError,
      );
    });

    test('clearSession also wipes the history timeline', () {
      final tracker = McpLoadedToolsTracker();
      addTearDown(tracker.dispose);
      tracker.absorb(
        sessionId: 's',
        loadedNamesRaw: <String>['mcp__a'],
      );
      expect(tracker.historyForSession('s'), hasLength(1));

      tracker.clearSession('s');
      expect(tracker.historyForSession('s'), isEmpty);
    });
  });
}
