import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/service/mcp_node_package_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late Directory homeDirectory;
  late Directory nvmDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-mcp-node-resolver-',
    );
    homeDirectory = Directory(p.join(temporaryDirectory.path, 'home'));
    nvmDirectory = Directory(p.join(homeDirectory.path, '.nvm'));
    await nvmDirectory.create(recursive: true);
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('normalizes package versions and rejects path traversal', () {
    expect(normalizeMcpNodePackageName('example@latest'), 'example');
    expect(
      normalizeMcpNodePackageName('@scope/example@1.2.3'),
      '@scope/example',
    );
    expect(normalizeMcpNodePackageName('../example'), isNull);
    expect(normalizeMcpNodePackageName('@../example'), isNull);
    expect(normalizeMcpNodePackageName(r'..\example'), isNull);
  });

  test('shell token quoting preserves embedded single quotes', () {
    expect(quoteMcpShellToken("alpha'beta"), r"'alpha'\''beta'");
  });

  test('prefers the newest bounded nvm runtime candidate', () async {
    Future<void> install(String version) async {
      final runtime = Directory(
        p.join(nvmDirectory.path, 'versions', 'node', version),
      );
      final node = File(p.join(runtime.path, 'bin', 'node'));
      final packageDirectory = Directory(
        p.join(runtime.path, 'lib', 'node_modules', '@scope', 'example'),
      );
      final entry = File(p.join(packageDirectory.path, 'bin', 'start.js'));
      await node.parent.create(recursive: true);
      await node.writeAsString('');
      await entry.parent.create(recursive: true);
      await entry.writeAsString('');
      await File(
        p.join(packageDirectory.path, 'package.json'),
      ).writeAsString(jsonEncode(<String, Object?>{'bin': 'bin/start.js'}));
    }

    await install('v20.1.0');
    await install('v22.3.0');

    final resolved = await resolveInstalledMcpNodePackage(
      '@scope/example@latest',
      homeDirectory: homeDirectory.path,
      nvmDirectory: nvmDirectory.path,
    );

    expect(resolved, isNotNull);
    expect(resolved!.nodeBin, contains('v22.3.0'));
    expect(resolved.entryScript, endsWith(p.join('bin', 'start.js')));
  });
}
