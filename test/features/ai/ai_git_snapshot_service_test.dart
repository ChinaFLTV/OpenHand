import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/git/ai_git_snapshot_service.dart';

void main() {
  test(
    'snapshot cache evicts the least recently used working directory',
    () async {
      final calls = <String, int>{};
      final service = AiGitSnapshotService(
        cacheTtl: const Duration(minutes: 1),
        cacheMaxEntries: 2,
        processRunner:
            (executable, arguments, {required workingDirectory}) async {
              calls.update(
                workingDirectory,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
              return ProcessResult(1, 0, 'false\n', '');
            },
      );

      await service.loadSnapshot(workingDirectory: '/workspace/one');
      await service.loadSnapshot(workingDirectory: '/workspace/two');
      await service.loadSnapshot(workingDirectory: '/workspace/one');
      await service.loadSnapshot(workingDirectory: '/workspace/three');
      await service.loadSnapshot(workingDirectory: '/workspace/two');

      expect(calls['/workspace/one'], 1);
      expect(calls['/workspace/two'], 2);
      expect(calls['/workspace/three'], 1);
    },
  );
}
