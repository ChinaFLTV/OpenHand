import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_artifacts.dart';

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand_web_artifacts_test_',
    );
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  test('concurrent initialization and close remain idempotent', () async {
    final artifacts = WebReverseSessionArtifacts(
      rootDir: temporaryDirectory.path,
      flushInterval: const Duration(hours: 1),
    );

    await Future.wait<void>(<Future<void>>[
      artifacts.init(),
      artifacts.init(),
      artifacts.init(),
    ]);
    artifacts.appendNetwork(<String, Object?>{'kind': 'request', 'id': 1});
    artifacts.appendConsole(<String, Object?>{'level': 'info', 'text': 'ok'});
    final firstClose = artifacts.close();
    final secondClose = artifacts.close();
    expect(identical(firstClose, secondClose), isTrue);
    await firstClose;
    expect(identical(firstClose, artifacts.close()), isTrue);

    final networkLines = await File(
      '${temporaryDirectory.path}/network.jsonl',
    ).readAsLines();
    final consoleLines = await File(
      '${temporaryDirectory.path}/console.jsonl',
    ).readAsLines();
    expect(jsonDecode(networkLines.single), <String, Object?>{
      'kind': 'request',
      'id': 1,
    });
    expect(jsonDecode(consoleLines.single), <String, Object?>{
      'level': 'info',
      'text': 'ok',
    });

    await artifacts.init();
    artifacts.appendNetwork(<String, Object?>{'kind': 'late'});
    expect(
      await File('${temporaryDirectory.path}/network.jsonl').readAsLines(),
      networkLines,
    );
  });

  test('invalid and oversized JSONL events are dropped safely', () async {
    final artifacts = WebReverseSessionArtifacts(
      rootDir: temporaryDirectory.path,
      flushInterval: const Duration(hours: 1),
    );
    await artifacts.init();

    final previousDebugPrint = debugPrint;
    debugPrint = (String? _, {int? wrapWidth}) {};
    try {
      expect(
        () => artifacts.appendNetwork(<String, Object?>{'invalid': Object()}),
        returnsNormally,
      );
      artifacts.appendNetwork(<String, Object?>{'kind': 'accepted'});
      artifacts.appendNetwork(<String, Object?>{
        'payload': List<String>.filled(1024 * 1024 + 1, 'x').join(),
      });
    } finally {
      debugPrint = previousDebugPrint;
    }
    await artifacts.close();

    final lines = await File(
      '${temporaryDirectory.path}/network.jsonl',
    ).readAsLines();
    expect(lines, hasLength(1));
    expect(jsonDecode(lines.single), <String, Object?>{'kind': 'accepted'});
  });

  test('close during initialization prevents late resource creation', () async {
    final root = '${temporaryDirectory.path}/nested/session';
    final artifacts = WebReverseSessionArtifacts(
      rootDir: root,
      flushInterval: const Duration(hours: 1),
    );

    final initializing = artifacts.init();
    await artifacts.close();
    await initializing;
    artifacts.appendConsole(<String, Object?>{'text': 'late'});

    final consoleFile = File('$root/console.jsonl');
    if (await consoleFile.exists()) {
      expect(await consoleFile.length(), 0);
    }
  });
}
