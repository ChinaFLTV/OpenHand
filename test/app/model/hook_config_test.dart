import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/hook_config.dart';

void main() {
  group('HookEntry', () {
    test('fromJson clamps timeout and falls back unknown events', () {
      final entry = HookEntry.fromJson(<String, Object?>{
        'id': 'hook-1',
        'event': 'unknown',
        'label': 'Hook',
        'enabled': 'false',
        'timeout_seconds': 999,
      });

      expect(entry.id, 'hook-1');
      expect(entry.event, HookEvent.sessionStart);
      expect(entry.enabled, isFalse);
      expect(entry.timeoutSeconds, HookEntry.maxTimeoutSeconds);
    });

    test('fromJson accepts JSON text payloads', () {
      final entry = HookEntry.fromJson(
        '{"id":"hook-2","event":"post_tool_use","timeout_seconds":0}',
      );

      expect(entry.id, 'hook-2');
      expect(entry.event, HookEvent.postToolUse);
      expect(entry.timeoutSeconds, HookEntry.minTimeoutSeconds);
    });

    test('copyWith and toJson normalize timeout seconds', () {
      const entry = HookEntry(
        id: 'hook-3',
        event: HookEvent.stop,
        label: 'Stop',
        timeoutSeconds: -5,
      );

      expect(entry.copyWith().timeoutSeconds, HookEntry.minTimeoutSeconds);
      expect(
        entry.copyWith(timeoutSeconds: 999).timeoutSeconds,
        HookEntry.maxTimeoutSeconds,
      );
      expect(entry.toJson()['timeout_seconds'], HookEntry.minTimeoutSeconds);
    });

    test('hasScript reports file or inline sources only', () {
      const empty = HookEntry(
        id: 'hook-4',
        event: HookEvent.stop,
        label: 'Empty',
      );
      final file = empty.copyWith(scriptPath: '/tmp/hook.sh');
      final inline = empty.copyWith(scriptContent: 'echo ok');

      expect(empty.hasScript, isFalse);
      expect(file.hasScript, isTrue);
      expect(inline.hasScript, isTrue);
    });
  });
}
