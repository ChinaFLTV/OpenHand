import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/physical_path_safety.dart';
import 'package:path/path.dart' as p;

void main() {
  group('isPhysicalPathWithinOrEqual', () {
    late Directory temporaryDirectory;
    late Directory workspace;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'openhand-path-safety-',
      );
      workspace = await Directory(
        p.join(temporaryDirectory.path, 'workspace'),
      ).create();
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('allows existing and missing descendants', () async {
      final existing = await Directory(
        p.join(workspace.path, 'existing'),
      ).create();

      expect(
        await isPhysicalPathWithinOrEqual(workspace.path, existing.path),
        isTrue,
      );
      expect(
        await isPhysicalPathWithinOrEqual(
          workspace.path,
          p.join(existing.path, 'new', 'file.txt'),
        ),
        isTrue,
      );
    });

    test(
      'blocks existing and missing descendants behind an escaping symlink',
      () async {
        final outside = await Directory(
          p.join(temporaryDirectory.path, 'outside'),
        ).create();
        await File(p.join(outside.path, 'secret.txt')).writeAsString('secret');
        final escape = Link(p.join(workspace.path, 'escape'));
        await escape.create(outside.path);

        expect(
          await isPhysicalPathWithinOrEqual(
            workspace.path,
            p.join(escape.path, 'secret.txt'),
          ),
          isFalse,
        );
        expect(
          await isPhysicalPathWithinOrEqual(
            workspace.path,
            p.join(escape.path, 'new.txt'),
          ),
          isFalse,
        );
      },
      skip: Platform.isWindows
          ? 'Creating symbolic links requires additional Windows privileges.'
          : false,
    );

    test(
      'allows a symlink whose physical target remains in the workspace',
      () async {
        final target = await Directory(
          p.join(workspace.path, 'target'),
        ).create();
        final link = Link(p.join(workspace.path, 'internal-link'));
        await link.create(target.path);

        expect(
          await isPhysicalPathWithinOrEqual(
            workspace.path,
            p.join(link.path, 'new.txt'),
          ),
          isTrue,
        );
      },
      skip: Platform.isWindows
          ? 'Creating symbolic links requires additional Windows privileges.'
          : false,
    );

    test('fails closed for missing roots and null bytes', () async {
      expect(
        await isPhysicalPathWithinOrEqual(
          p.join(temporaryDirectory.path, 'missing-root'),
          p.join(temporaryDirectory.path, 'missing-root', 'file.txt'),
        ),
        isFalse,
      );
      expect(
        await isPhysicalPathWithinOrEqual(
          workspace.path,
          '${workspace.path}\u0000/file.txt',
        ),
        isFalse,
      );
    });
  });
}
