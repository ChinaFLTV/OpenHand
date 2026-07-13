import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';

void main() {
  test('ignores an oversized hook configuration', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-hook-config-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final projectDirectory = Directory('${temporaryDirectory.path}/project');
    final configDirectory = Directory('${projectDirectory.path}/.claude');
    await configDirectory.create(recursive: true);
    await File(
      '${configDirectory.path}/settings.json',
    ).writeAsString('x' * (2 * 1024 * 1024 + 1));
    final service = AiClaudeHookService(
      applicationDirectoryPath: () => projectDirectory.path,
      homeDirectoryPath: () => '${temporaryDirectory.path}/home',
      configPresenceCacheTtl: Duration.zero,
    );

    final result = await service.runHooks(
      eventName: 'PreToolUse',
      sessionId: 'session',
      payload: const <String, Object?>{},
      cwd: projectDirectory.path,
    );

    expect(result.executedHookCount, 0);
    expect(result.loadedConfigPaths, isEmpty);
  });
}
