import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/directory_cleanup.dart';
import 'package:path/path.dart' as p;

void main() {
  group('isDirectoryEmpty', () {
    test('handles missing, empty, and non-empty directories', () async {
      final root = await Directory.systemTemp.createTemp(
        'openhand_directory_empty_test_',
      );
      try {
        final empty = Directory(p.join(root.path, 'empty'));
        final nonEmpty = Directory(p.join(root.path, 'non-empty'));
        await empty.create();
        await nonEmpty.create();
        await File(p.join(nonEmpty.path, 'file.txt')).writeAsString('data');

        expect(
          await isDirectoryEmpty(Directory(p.join(root.path, 'missing'))),
          isFalse,
        );
        expect(await isDirectoryEmpty(empty), isTrue);
        expect(await isDirectoryEmpty(nonEmpty), isFalse);
      } finally {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      }
    });
  });

  group('deleteEmptyAncestorDirectories', () {
    test('deletes empty ancestors up to but not including stopAt', () async {
      final root = await Directory.systemTemp.createTemp(
        'openhand_directory_cleanup_test_',
      );
      try {
        final stop = await Directory(p.join(root.path, 'stop')).create();
        final parent = await Directory(p.join(stop.path, 'parent')).create();
        final leaf = await Directory(p.join(parent.path, 'leaf')).create();

        await deleteEmptyAncestorDirectories(start: leaf, stopAt: stop);

        expect(await leaf.exists(), isFalse);
        expect(await parent.exists(), isFalse);
        expect(await stop.exists(), isTrue);
      } finally {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      }
    });

    test('stops when an ancestor is non-empty', () async {
      final root = await Directory.systemTemp.createTemp(
        'openhand_directory_cleanup_test_',
      );
      try {
        final stop = await Directory(p.join(root.path, 'stop')).create();
        final parent = await Directory(p.join(stop.path, 'parent')).create();
        final leaf = await Directory(p.join(parent.path, 'leaf')).create();
        await File(p.join(parent.path, 'keep.txt')).writeAsString('data');

        await deleteEmptyAncestorDirectories(start: leaf, stopAt: stop);

        expect(await leaf.exists(), isFalse);
        expect(await parent.exists(), isTrue);
        expect(await stop.exists(), isTrue);
      } finally {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      }
    });

    test('can continue past missing start directories', () async {
      final root = await Directory.systemTemp.createTemp(
        'openhand_directory_cleanup_test_',
      );
      try {
        final stop = await Directory(p.join(root.path, 'stop')).create();
        final parent = await Directory(p.join(stop.path, 'parent')).create();
        final missingStart = Directory(p.join(parent.path, 'missing', 'leaf'));

        await deleteEmptyAncestorDirectories(start: missingStart, stopAt: stop);

        expect(await parent.exists(), isFalse);
        expect(await stop.exists(), isTrue);
      } finally {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      }
    });

    test('can stop at a missing start directory', () async {
      final root = await Directory.systemTemp.createTemp(
        'openhand_directory_cleanup_test_',
      );
      try {
        final stop = await Directory(p.join(root.path, 'stop')).create();
        final parent = await Directory(p.join(stop.path, 'parent')).create();
        final missingStart = Directory(p.join(parent.path, 'missing', 'leaf'));

        await deleteEmptyAncestorDirectories(
          start: missingStart,
          stopAt: stop,
          continuePastMissing: false,
        );

        expect(await parent.exists(), isTrue);
        expect(await stop.exists(), isTrue);
      } finally {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      }
    });
  });
}
