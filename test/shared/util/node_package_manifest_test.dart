import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/node_package_manifest.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory packageDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-node-manifest-',
    );
    packageDirectory = Directory('${temporaryDirectory.path}/package');
    await Directory('${packageDirectory.path}/bin').create(recursive: true);
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('resolves a package-local bin entry', () async {
    final entry = File('${packageDirectory.path}/bin/start.js');
    await entry.writeAsString('');
    await File('${packageDirectory.path}/package.json').writeAsString(
      jsonEncode(<String, Object?>{
        'bin': <String, String>{'openhand-test': 'bin/start.js'},
      }),
    );

    expect(await resolveNodePackageBinEntry(packageDirectory.path), entry.path);
  });

  test('rejects a bin entry outside the package directory', () async {
    final outside = File('${temporaryDirectory.path}/outside.js');
    await outside.writeAsString('');
    await File(
      '${packageDirectory.path}/package.json',
    ).writeAsString(jsonEncode(<String, Object?>{'bin': '../outside.js'}));

    expect(await resolveNodePackageBinEntry(packageDirectory.path), isNull);
  });

  test('rejects an oversized package manifest', () async {
    await File(
      '${packageDirectory.path}/package.json',
    ).writeAsString('{"bin":"bin/start.js"}');

    expect(
      await resolveNodePackageBinEntry(
        packageDirectory.path,
        maxManifestBytes: 8,
      ),
      isNull,
    );
  });

  test('rejects a symbolic-link bin entry', () async {
    final outside = File('${temporaryDirectory.path}/outside.js');
    await outside.writeAsString('');
    final linkedEntry = Link('${packageDirectory.path}/bin/start.js');
    await linkedEntry.create(outside.path);
    await File(
      '${packageDirectory.path}/package.json',
    ).writeAsString(jsonEncode(<String, Object?>{'bin': 'bin/start.js'}));

    expect(await resolveNodePackageBinEntry(packageDirectory.path), isNull);
  });
}
