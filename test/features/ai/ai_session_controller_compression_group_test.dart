import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';

void main() {
  test('groups tool calls with their results for compression windows', () {
    final messages = <AiSessionMessage>[
      _user('u1'),
      _toolCall('tc1'),
      _toolResult('tr1'),
      _toolCall('tc2'),
      _toolResult('tr2'),
      _assistant('a1'),
    ];

    final groups = groupSessionMessagesForCompression(messages);

    expect(_ids(groups), <List<String>>[
      <String>['u1'],
      <String>['tc1', 'tr1'],
      <String>['tc2', 'tr2'],
      <String>['a1'],
    ]);
  });

  test('keeps assistant text and following tool call in the same group', () {
    final messages = <AiSessionMessage>[
      _user('u1'),
      _assistant('a1'),
      _toolCall('tc1'),
      _toolResult('tr1'),
      _assistant('a2'),
    ];

    final groups = groupSessionMessagesForCompression(messages);

    expect(_ids(groups), <List<String>>[
      <String>['u1'],
      <String>['a1', 'tc1', 'tr1'],
      <String>['a2'],
    ]);
  });

  test('prompt-too-long retry drops whole oldest groups', () {
    final messages = <AiSessionMessage>[
      _user('u1'),
      _toolCall('tc1'),
      _toolResult('tr1'),
      _toolCall('tc2'),
      _toolResult('tr2'),
      _assistant('a1'),
    ];

    final retryWindow = retryCompressionWindowAfterPromptTooLong(messages)!;

    expect(retryWindow.discardedMessages.map((message) => message.id), <String>[
      'u1',
    ]);
    expect(
      retryWindow.messagesToCompress.map((message) => message.id),
      <String>['tc1', 'tr1', 'tc2', 'tr2', 'a1'],
    );
  });

  test('retention expands to keep recent text anchors', () {
    final messages = <AiSessionMessage>[
      _user('u0'),
      _assistant('a0'),
      _user('u1'),
      _assistant('a1'),
      _user('u2'),
      _assistant('a2'),
      _user('u3'),
      _assistant('a3'),
    ];

    final retained = retainedSessionMessageGroupsForCompression(
      messages,
      threshold: 30,
    );

    expect(_ids(retained), <List<String>>[
      <String>['a1', 'u2'],
      <String>['a2', 'u3'],
      <String>['a3'],
    ]);
  });

  test('normalizes compact summary XML drafting blocks', () {
    final normalized = normalizeCompressionCheckpointSummary('''
<analysis>
This scratchpad should not be persisted.
</analysis>

<summary>
## Objective
Continue the compression work.

## User Messages
- Keep user constraints.
</summary>
''');

    expect(normalized, isNot(contains('scratchpad')));
    expect(normalized, isNot(contains('<summary>')));
    expect(normalized, startsWith('## Objective'));
    expect(normalized, contains('## User Messages'));
  });
}

List<List<String>> _ids(List<List<AiSessionMessage>> groups) {
  return groups
      .map(
        (group) => group.map((message) => message.id).toList(growable: false),
      )
      .toList(growable: false);
}

AiSessionMessage _user(String id) {
  return AiSessionMessage.user(
    id: id,
    content: 'user $id',
    createdAt: DateTime.utc(2026, 5, 3),
  );
}

AiSessionMessage _assistant(String id) {
  return AiSessionMessage.assistant(
    id: id,
    content: 'assistant $id',
    createdAt: DateTime.utc(2026, 5, 3),
  );
}

AiSessionMessage _toolCall(String id) {
  return AiSessionMessage.toolCall(
    id: id,
    content: 'tool call $id',
    createdAt: DateTime.utc(2026, 5, 3),
    metadata: const <String, Object?>{},
  );
}

AiSessionMessage _toolResult(String id) {
  return AiSessionMessage.toolResult(
    id: id,
    content: 'tool result $id',
    createdAt: DateTime.utc(2026, 5, 3),
    metadata: const <String, Object?>{},
  );
}
