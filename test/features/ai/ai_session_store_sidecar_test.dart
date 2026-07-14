import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/shared/util/bounded_file_io.dart';

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;
  late AiSessionStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-session-sidecar-',
    );
    store = AiSessionStore(sessionsDirectoryPath: temporaryDirectory.path);
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  Future<void> writeSidecar({required String metadata}) async {
    final markdown = File(store.sessionCompactMemoryMarkdownPath('session-1'));
    await markdown.parent.create(recursive: true);
    await markdown.writeAsString('# Memory\n\n## Summary\n\nsummary');
    await File(
      store.sessionCompactMemoryMetadataPath('session-1'),
    ).writeAsString(metadata);
  }

  test('loads bounded compact memory sidecars', () async {
    await writeSidecar(
      metadata: jsonEncode(<String, Object?>{
        'checkpoint_message_id': 'checkpoint-1',
      }),
    );

    final sidecar = await store.loadCompressionMemorySidecar('session-1');

    expect(sidecar?.checkpointMessageId, 'checkpoint-1');
    expect(sidecar?.summaryContent, 'summary');
  });

  test('corrupt metadata does not discard valid markdown', () async {
    await writeSidecar(metadata: '{invalid');

    final sidecar = await store.loadCompressionMemorySidecar('session-1');

    expect(sidecar?.markdown, contains('summary'));
    expect(sidecar?.metadata, isEmpty);
  });

  test('oversized markdown is rejected before allocation', () async {
    final markdown = File(store.sessionCompactMemoryMarkdownPath('session-1'));
    await markdown.parent.create(recursive: true);
    final handle = await markdown.open(mode: FileMode.write);
    await handle.truncate(16 * 1024 * 1024 + 1);
    await handle.close();

    await expectLater(
      store.loadCompressionMemorySidecar('session-1'),
      throwsA(isA<BoundedFileReadException>()),
    );
  });
}
