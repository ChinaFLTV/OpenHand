import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/service/self_learning_scheduler.dart';
import 'package:openhand/shared/data/database_service.dart';
import 'package:path/path.dart' as p;

AiSession _buildSession({
  required String id,
  required String templateId,
  required DateTime createdAt,
  required List<AiSessionMessage> messages,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return AiSession(
    id: id,
    title: 'Test session $id',
    templateId: templateId,
    templateName: 'Test',
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

void main() {
  late Directory tempDir;
  late AiSessionStore store;
  late SettingsController settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('slsched_');
    await DatabaseService.initialize(
      databasePath: p.join(tempDir.path, 'openhand.db'),
    );
    store = AiSessionStore(sessionsDirectoryPath: tempDir.path);
    settings = await SettingsController.create();
    // Default is true but be explicit.
    await settings.updateSelfLearningEnabled(true);
  });

  tearDown(() async {
    settings.dispose();
    if (DatabaseService.isInitialized) {
      await DatabaseService.instance.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SelfLearningScheduler', () {
    test('returns zeros when feature disabled', () async {
      await settings.updateSelfLearningEnabled(false);
      final now = DateTime.now().toUtc();
      await store.save(
        _buildSession(
          id: 'sess1',
          templateId: 'hermes_talker',
          createdAt: now,
          messages: _sixTurns(now),
        ),
      );
      final dispatched = <String>[];
      final scheduler = SelfLearningScheduler(
        sessionStore: store,
        settingsController: settings,
        runForSession: (s) async => dispatched.add(s.id),
      );
      final result = await scheduler.tick(now: now);
      expect(result.scanned, 0);
      expect(result.triggered, 0);
      expect(dispatched, isEmpty);
    });

    test('triggers runner for eligible Hermes Talker session', () async {
      final now = DateTime.now().toUtc();
      await store.save(
        _buildSession(
          id: 'sess-eligible',
          templateId: 'hermes_talker',
          createdAt: now,
          messages: _sixTurns(now),
        ),
      );
      final dispatched = <String>[];
      final scheduler = SelfLearningScheduler(
        sessionStore: store,
        settingsController: settings,
        runForSession: (s) async => dispatched.add(s.id),
      );
      final result = await scheduler.tick(now: now);
      expect(result.scanned, 1);
      expect(result.triggered, 1);
      expect(result.skipped, 0);
      expect(dispatched, ['sess-eligible']);
    });

    test('skips sessions whose last message is already selfLearning', () async {
      final now = DateTime.now().toUtc();
      final msgs = _sixTurns(now)
        ..add(
          AiSessionMessage.selfLearning(
            id: 'sl1',
            content: 'ok',
            createdAt: now.add(const Duration(minutes: 30)),
            metadata: const <String, Object?>{'status': 'ok'},
          ),
        );
      await store.save(
        _buildSession(
          id: 'sess-done',
          templateId: 'hermes_talker',
          createdAt: now,
          messages: msgs,
        ),
      );
      final dispatched = <String>[];
      final scheduler = SelfLearningScheduler(
        sessionStore: store,
        settingsController: settings,
        runForSession: (s) async => dispatched.add(s.id),
      );
      final result = await scheduler.tick(now: now);
      expect(result.scanned, 1);
      expect(result.triggered, 0);
      expect(result.skipped, 1);
      expect(dispatched, isEmpty);
    });

    test('skips sessions with fewer than 4 messages', () async {
      final now = DateTime.now().toUtc();
      await store.save(
        _buildSession(
          id: 'sess-short',
          templateId: 'hermes_talker',
          createdAt: now,
          messages: <AiSessionMessage>[
            AiSessionMessage.user(id: 'u0', content: 'hi', createdAt: now),
            AiSessionMessage.assistant(
              id: 'a0',
              content: 'hello',
              createdAt: now,
            ),
          ],
        ),
      );
      final dispatched = <String>[];
      final scheduler = SelfLearningScheduler(
        sessionStore: store,
        settingsController: settings,
        runForSession: (s) async => dispatched.add(s.id),
      );
      final result = await scheduler.tick(now: now);
      expect(result.scanned, 1);
      expect(result.skipped, 1);
      expect(dispatched, isEmpty);
    });

    test('skips sessions flagged self_learning_in_progress', () async {
      final now = DateTime.now().toUtc();
      await store.save(
        _buildSession(
          id: 'sess-busy',
          templateId: 'hermes_talker',
          createdAt: now,
          messages: _sixTurns(now),
          metadata: const <String, Object?>{'self_learning_in_progress': true},
        ),
      );
      final dispatched = <String>[];
      final scheduler = SelfLearningScheduler(
        sessionStore: store,
        settingsController: settings,
        runForSession: (s) async => dispatched.add(s.id),
      );
      final result = await scheduler.tick(now: now);
      expect(result.triggered, 0);
      expect(result.skipped, 1);
      expect(dispatched, isEmpty);
    });

    test('ignores sessions older than 7-day lookback', () async {
      final now = DateTime.now().toUtc();
      final old = now.subtract(const Duration(days: 8));
      await store.save(
        _buildSession(
          id: 'sess-old',
          templateId: 'hermes_talker',
          createdAt: old,
          messages: _sixTurns(old),
        ),
      );
      final dispatched = <String>[];
      final scheduler = SelfLearningScheduler(
        sessionStore: store,
        settingsController: settings,
        runForSession: (s) async => dispatched.add(s.id),
      );
      final result = await scheduler.tick(now: now);
      expect(result.scanned, 0);
      expect(dispatched, isEmpty);
    });

    test('ignores sessions from other templates', () async {
      final now = DateTime.now().toUtc();
      await store.save(
        _buildSession(
          id: 'sess-other',
          templateId: 'default',
          createdAt: now,
          messages: _sixTurns(now),
        ),
      );
      final dispatched = <String>[];
      final scheduler = SelfLearningScheduler(
        sessionStore: store,
        settingsController: settings,
        runForSession: (s) async => dispatched.add(s.id),
      );
      final result = await scheduler.tick(now: now);
      expect(result.scanned, 0);
      expect(dispatched, isEmpty);
    });

    test(
      'counts errors thrown by runForSession without aborting tick',
      () async {
        final now = DateTime.now().toUtc();
        for (final id in ['a', 'b', 'c']) {
          await store.save(
            _buildSession(
              id: 'sess-$id',
              templateId: 'hermes_talker',
              createdAt: now,
              messages: _sixTurns(now, idPrefix: '$id-'),
            ),
          );
        }
        final dispatched = <String>[];
        final scheduler = SelfLearningScheduler(
          sessionStore: store,
          settingsController: settings,
          runForSession: (s) async {
            dispatched.add(s.id);
            if (s.id == 'sess-b') throw StateError('boom');
          },
        );
        final result = await scheduler.tick(now: now);
        expect(result.triggered, 3);
        expect(result.errors, 1);
        expect(dispatched.length, 3);
      },
    );

    test(
      'updateConcurrency clamps to [1, 10] and updates the semaphore',
      () async {
        final scheduler = SelfLearningScheduler(
          sessionStore: store,
          settingsController: settings,
          runForSession: (_) async {},
          concurrency: 3,
        );
        // Smoke-test: should not throw, and subsequent ticks should still work.
        scheduler.updateConcurrency(0); // clamped to 1
        scheduler.updateConcurrency(999); // clamped to 10
        scheduler.updateConcurrency(5);
        final result = await scheduler.tick(now: DateTime.now().toUtc());
        expect(result.scanned, 0);
      },
    );
  });
}
