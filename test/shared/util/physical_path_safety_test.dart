import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/node_package_manifest.dart';
import 'package:openhand/shared/util/physical_path_safety.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'physical containment rejects paths through an escaping symlink',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'openhand-path-safety-',
      );
      final root = Directory(p.join(sandbox.path, 'root'));
      final outside = Directory(p.join(sandbox.path, 'outside'));
      await root.create();
      await outside.create();
      try {
        final inside = p.join(root.path, 'new', 'file.txt');
        expect(await isPhysicalPathWithinOrEqual(root.path, inside), isTrue);

        final link = Link(p.join(root.path, 'escape'));
        await link.create(outside.path);
        expect(
          await isPhysicalPathWithinOrEqual(
            root.path,
            p.join(link.path, 'file.txt'),
          ),
          isFalse,
        );
      } finally {
        await sandbox.delete(recursive: true);
      }
    },
    skip: Platform.isWindows
        ? 'Creating symbolic links requires elevated Windows privileges.'
        : false,
  );

  test(
    'Node package bin resolution rejects an escaping intermediate symlink',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'openhand-node-bin-',
      );
      final packageRoot = Directory(p.join(sandbox.path, 'package'));
      final outside = Directory(p.join(sandbox.path, 'outside'));
      await packageRoot.create();
      await outside.create();
      await File(p.join(outside.path, 'cli.js')).writeAsString('cli');
      await File(
        p.join(packageRoot.path, 'package.json'),
      ).writeAsString(jsonEncode(<String, Object?>{'bin': 'linked/cli.js'}));
      try {
        await Link(p.join(packageRoot.path, 'linked')).create(outside.path);
        expect(await resolveNodePackageBinEntry(packageRoot.path), isNull);
      } finally {
        await sandbox.delete(recursive: true);
      }
    },
    skip: Platform.isWindows
        ? 'Creating symbolic links requires elevated Windows privileges.'
        : false,
  );
}
