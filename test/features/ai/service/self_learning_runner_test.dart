import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/service/self_learning_runner.dart';
import 'package:openhand/features/memory/memory_controller.dart';
import 'package:openhand/shared/data/database_service.dart';
import 'package:path/path.dart' as p;

AiSession _buildSession({
  required String id,
  required DateTime createdAt,
  required List<AiSessionMessage> messages,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return AiSession(
    id: id,
    title: 'Runner test $id',
    templateId: 'hermes_talker',
    templateName: 'Hermes Talker',
    templateIconName: 'forum_rounded',
    templateInternalVersion: '1.0.0',
    createdAt: createdAt,
    updatedAt: createdAt,
    messages: messages,
    environment: const AiSessionEnvironment(
      localeTag: 'en',
      platform: 'test',
      appVersion: '0.0.0',
      appBuildNumber: '0',
      applicationDirectory: '',
      homeDirectory: '',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: '',
      compressionThresholdChars: 0,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const [],
    metadata: metadata,
  );
}

List<AiSessionMessage> _sixTurns(DateTime baseTime, {String idPrefix = ''}) {
  final msgs = <AiSessionMessage>[];
  for (var i = 0; i < 6; i++) {
    msgs.add(
      AiSessionMessage.user(
        id: '${idPrefix}u$i',
        content: 'user msg $i',
        createdAt: baseTime.add(Duration(minutes: i * 2)),
      ),
    );
    msgs.add(
      AiSessionMessage.assistant(
        id: '${idPrefix}a$i',
        content: 'assistant reply $i',
        createdAt: baseTime.add(Duration(minutes: i * 2 + 1)),
      ),
    );
  }
  return msgs;
}

AiSessionMessage? _lastSelfLearning(AiSession s) {
  for (var i = s.messages.length - 1; i >= 0; i--) {
    final m = s.messages[i];
    if (m.isDeleted) continue;
    if (m.kind == AiSessionMessageKind.selfLearning) return m;
  }
  return null;
}

void main() {
  late Directory tempDir;
  late AiSessionStore store;
  late AiSessionController sessionController;
  late MemoryController memoryController;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('slrunner_');
    await DatabaseService.initialize(
      databasePath: p.join(tempDir.path, 'openhand.db'),
    );
    store = AiSessionStore(sessionsDirectoryPath: tempDir.path);
    sessionController = await AiSessionController.create(store: store);
    memoryController = await MemoryController.create();
  });

  tearDown(() async {
    sessionController.dispose();
    memoryController.dispose();
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SelfLearningRunner', () {
    test('writes skipped card when turn count below threshold', () async {
      final now = DateTime.now().toUtc();
      final session = _buildSession(
        id: 'sess-short',
        createdAt: now,
        messages: <AiSessionMessage>[
          AiSessionMessage.user(id: 'u0', content: 'hi', createdAt: now),
          AiSessionMessage.assistant(
            id: 'a0',
            content: 'hello',
            createdAt: now.add(const Duration(seconds: 1)),
          ),
        ],
      );
      await store.save(session);
      await sessionController.refresh();

      var dispatcherCalls = 0;
      final runner = SelfLearningRunner(
        sessionController: sessionController,
        memoryController: memoryController,
        llmDispatcher: (_) async {
          dispatcherCalls += 1;
          return const SelfLearningOutcome(summary: 'should-not-run');
        },
      );
      await runner.runForSession(session);
      expect(dispatcherCalls, 0);

      final reloaded = sessionController.sessionById('sess-short')!;
      final card = _lastSelfLearning(reloaded)!;
      expect(card.metadata['status'], 'skipped');
      expect(card.content, contains('对话轮次不足'));
      expect(card.metadata['conversation_turns'], 2);
      expect(reloaded.metadata['self_learning_in_progress'], false);
    });

    test(
      'writes skipped card + context snapshot when dispatcher missing',
      () async {
        final now = DateTime.now().toUtc();
        final session = _buildSession(
          id: 'sess-no-disp',
          createdAt: now,
          messages: _sixTurns(now),
        );
        await store.save(session);
        await sessionController.refresh();

        final runner = SelfLearningRunner(
          sessionController: sessionController,
          memoryController: memoryController,
        );
        await runner.runForSession(session);

        final reloaded = sessionController.sessionById('sess-no-disp')!;
        final card = _lastSelfLearning(reloaded)!;
        expect(card.metadata['status'], 'skipped');
        expect(card.content, contains('未配置 LLM'));
        expect(card.metadata['conversation_turns'], 12);
        expect(card.metadata['user_profile_present'], false);
        expect(card.metadata['auto_learned_count'], 0);
        expect(reloaded.metadata['self_learning_in_progress'], false);
      },
    );

    test('writes ok card with dispatcher mutations on success', () async {
      final now = DateTime.now().toUtc();
      final session = _buildSession(
        id: 'sess-ok',
        createdAt: now,
        messages: _sixTurns(now, idPrefix: 'ok-'),
      );
      await store.save(session);
      await sessionController.refresh();

      SelfLearningContext? captured;
      final runner = SelfLearningRunner(
        sessionController: sessionController,
        memoryController: memoryController,
        llmDispatcher: (ctx) async {
          captured = ctx;
          return const SelfLearningOutcome(
            summary: '已学习 3 条记忆',
            mutations: <String, Object?>{
              'memory_updates': 3,
              'skill_updates': 0,
            },
          );
        },
      );
      await runner.runForSession(session);

      expect(captured, isNotNull);
      expect(captured!.conversationSlice, contains('user: user msg 0'));
      expect(
        captured!.conversationSlice,
        contains('assistant: assistant reply 5'),
      );
      expect(captured!.prompt, contains('自我学习'));

      final reloaded = sessionController.sessionById('sess-ok')!;
      final card = _lastSelfLearning(reloaded)!;
      expect(card.metadata['status'], 'ok');
      expect(card.content, '已学习 3 条记忆');
      expect(card.metadata['memory_updates'], 3);
      expect(reloaded.metadata['self_learning_in_progress'], false);
    });

    test(
      'writes error card and clears in-progress flag when dispatcher throws',
      () async {
        final now = DateTime.now().toUtc();
        final session = _buildSession(
          id: 'sess-err',
          createdAt: now,
          messages: _sixTurns(now, idPrefix: 'err-'),
        );
        await store.save(session);
        await sessionController.refresh();

        final runner = SelfLearningRunner(
          sessionController: sessionController,
          memoryController: memoryController,
          llmDispatcher: (_) async {
            throw StateError('boom');
          },
        );
        await runner.runForSession(session);

        final reloaded = sessionController.sessionById('sess-err')!;
        final card = _lastSelfLearning(reloaded)!;
        expect(card.metadata['status'], 'error');
        expect(card.content, contains('自我学习失败'));
        expect(card.metadata['error'], contains('boom'));
        expect(reloaded.metadata['self_learning_in_progress'], false);
      },
    );

    test(
      'slices conversation starting after the last selfLearning checkpoint',
      () async {
        final now = DateTime.now().toUtc();
        final messages = <AiSessionMessage>[
          // Old turns (should be excluded by slice).
          AiSessionMessage.user(
            id: 'old-u',
            content: 'OLD_USER',
            createdAt: now,
          ),
          AiSessionMessage.assistant(
            id: 'old-a',
            content: 'OLD_ASSISTANT',
            createdAt: now.add(const Duration(seconds: 1)),
          ),
          AiSessionMessage.selfLearning(
            id: 'checkpoint',
            content: 'previous learn',
            createdAt: now.add(const Duration(seconds: 2)),
            metadata: const <String, Object?>{'status': 'ok'},
          ),
          // New turns after the checkpoint — these should appear in the slice
          // and are enough to pass minConversationTurns=4.
          ..._sixTurns(now.add(const Duration(minutes: 10)), idPrefix: 'new-'),
        ];
        final session = _buildSession(
          id: 'sess-slice',
          createdAt: now,
          messages: messages,
        );
        await store.save(session);
        await sessionController.refresh();

        SelfLearningContext? captured;
        final runner = SelfLearningRunner(
          sessionController: sessionController,
          memoryController: memoryController,
          llmDispatcher: (ctx) async {
            captured = ctx;
            return const SelfLearningOutcome(summary: 'done');
          },
        );
        await runner.runForSession(session);

        expect(captured, isNotNull);
        expect(captured!.conversationSlice, isNot(contains('OLD_USER')));
        expect(captured!.conversationSlice, isNot(contains('OLD_ASSISTANT')));
        expect(captured!.conversationSlice, isNot(contains('previous learn')));
        expect(captured!.conversationSlice, contains('user: user msg 0'));
      },
    );
  });
}
