import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_profile_cleaner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-profile-cleaner-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('detects and removes regular profile locks', () async {
    final lock = File(p.join(temporaryDirectory.path, 'Default', 'lockfile'));
    await lock.parent.create(recursive: true);
    await lock.writeAsString('locked');

    expect(await hasWebReverseProfileLocks(temporaryDirectory.path), isTrue);
    final result = await cleanWebReverseProfileLocks(temporaryDirectory.path);

    expect(result.deleted, 1);
    expect(await lock.exists(), isFalse);
    expect(await hasWebReverseProfileLocks(temporaryDirectory.path), isFalse);
  });

  test('detects and removes dangling symbolic-link locks', () async {
    if (Platform.isWindows) return;
    final lock = Link(p.join(temporaryDirectory.path, 'SingletonLock'));
    await lock.create('host-12345');

    expect(await hasWebReverseProfileLocks(temporaryDirectory.path), isTrue);
    final result = await cleanWebReverseProfileLocks(temporaryDirectory.path);

    expect(result.deleted, 1);
    expect(
      await FileSystemEntity.type(lock.path, followLinks: false),
      FileSystemEntityType.notFound,
    );
  });

  test('does not treat a same-name directory as a removable lock', () async {
    final directory = Directory(
      p.join(temporaryDirectory.path, 'SingletonCookie'),
    );
    await directory.create();

    expect(await hasWebReverseProfileLocks(temporaryDirectory.path), isFalse);
    final result = await cleanWebReverseProfileLocks(temporaryDirectory.path);

    expect(result.deleted, 0);
    expect(await directory.exists(), isTrue);
  });
}
