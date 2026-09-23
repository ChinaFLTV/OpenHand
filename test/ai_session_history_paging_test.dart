import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/shared/db/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('工具调用跨页时历史分页保持有界且连续', () async {
    final directory = await Directory.systemTemp.createTemp('openhand-paging-');
    final database = await DatabaseService.initialize(
      databasePath: '${directory.path}/history.db',
      useNoIsolateFactory: true,
    );
    try {
      final db = database.database;
      const sessionId = 'history-paging';
      const timestamp = '2026-01-01T00:00:00.000Z';
      await db.insert('sessions', <String, Object?>{
        'id': sessionId,
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await db.transaction((txn) async {
        for (var index = 0; index < 600; index++) {
          final isCall = index == 0;
          final isResult = index == 60;
          await txn.insert('messages', <String, Object?>{
            'id': 'message-$index',
            'session_id': sessionId,
            'sort_order': index,
            'kind': isCall
                ? 'tool_call'
                : isResult
                ? 'tool'
                : 'assistant',
            'role': isResult ? 'tool' : 'assistant',
            'content': '消息 $index',
            'created_at': timestamp,
            'metadata_json': jsonEncode(
              isCall || isResult
                  ? <String, Object?>{'tool_call_id': 'paired-call'}
                  : <String, Object?>{},
            ),
          });
        }
      });

      final store = AiSessionStore(sessionsDirectoryPath: directory.path);
      final current = await store.loadMessages(
        sessionId,
        offset: 60,
        limit: 13,
        includeToolCallContext: false,
      );
      final earlier = await store.loadMessages(
        sessionId,
        offset: 48,
        limit: 13,
        includeToolCallContext: false,
      );
      expect(current.offset, 60);
      expect(current.messages.length, 13);
      expect(earlier.offset, 48);
      expect(earlier.messages.length, 13);
      expect(earlier.messages.last.id, current.messages.first.id);

      var boundaryId = 'message-588';
      for (var offset = 576; offset >= 0; offset -= 12) {
        final page = await store.loadMessages(
          sessionId,
          offset: offset,
          limit: 13,
          includeToolCallContext: false,
          deferTelemetryMetadata: true,
          contentPreviewChars: 4096,
        );
        expect(page.offset, offset);
        expect(page.messages.length, 13);
        expect(page.messages.last.id, boundaryId);
        expect(page.totalCount, 600);
        boundaryId = page.messages.first.id;
      }
      expect(boundaryId, 'message-0');
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
