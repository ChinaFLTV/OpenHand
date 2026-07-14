import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/ai_tool_utils.dart';

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-ai-tool-utils-',
    );
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  test(
    'missing-path suggestion selects a close regular-file sibling',
    () async {
      final candidate = File('${temporaryDirectory.path}/report.json');
      await candidate.writeAsString('{}');

      final suggestion = await AiToolUtils.suggestSiblingPath(
        '${temporaryDirectory.path}/report.jsonl',
      );

      expect(suggestion, candidate.path);
    },
  );

  test('missing-path suggestion returns null for a missing parent', () async {
    final suggestion = await AiToolUtils.suggestSiblingPath(
      '${temporaryDirectory.path}/missing/report.json',
    );

    expect(suggestion, isNull);
  });
}
