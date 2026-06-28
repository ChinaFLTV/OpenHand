import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/hook_config.dart';

void main() {
  test('HookEntry.fromJson accepts JSON text and clamps timeout', () {
    final entry = HookEntry.fromJson('''
      {
        "id": " hook-1 ",
        "event": "post_tool_use",
        "label": " audit ",
        "script_path": " /tmp/audit.sh ",
        "enabled": "off",
        "timeout_seconds": "999"
      }
    ''');

    expect(entry.id, 'hook-1');
    expect(entry.event, HookEvent.postToolUse);
    expect(entry.label, 'audit');
    expect(entry.scriptPath, '/tmp/audit.sh');
    expect(entry.enabled, isFalse);
    expect(entry.timeoutSeconds, HookEntry.maxTimeoutSeconds);
  });

  test('HookEntry.fromJson falls back for invalid event and timeout', () {
    final entry = HookEntry.fromJson(<Object?, Object?>{
      1: 'ignored',
      'id': 42,
      'event': 'missing',
      'script_content': '  echo ok  ',
      'timeout_seconds': '-1',
    });

    expect(entry.id, '42');
    expect(entry.event, HookEvent.sessionStart);
    expect(entry.scriptContent, 'echo ok');
    expect(entry.timeoutSeconds, HookEntry.minTimeoutSeconds);
  });
}
