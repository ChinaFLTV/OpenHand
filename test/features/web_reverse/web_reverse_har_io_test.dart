import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_har_io.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('openhand_har_io_');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('reads a bounded path without changing its bytes', () async {
    final file = File('${tempDirectory.path}/stable.har');
    const content = '{"log":{"entries":[]}}';
    await file.writeAsString(content);

    final result = await readWebReverseHarPath(file.path);

    expect(result.isTooLarge, isFalse);
    expect(String.fromCharCodes(result.bytes!), content);
  });

  test('rejects an oversized path before materializing it', () async {
    final file = File('${tempDirectory.path}/oversized.har');
    final handle = await file.open(mode: FileMode.write);
    await handle.setPosition(kWebReverseHarFileMaxBytes);
    await handle.writeByte(0);
    await handle.close();

    final result = await readWebReverseHarPath(file.path);

    expect(result.isTooLarge, isTrue);
    expect(result.tooLargeBytes, kWebReverseHarFileMaxBytes + 1);
  });

  test('rejects a FIFO path without waiting for a writer', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final path = '${tempDirectory.path}/stream.har';
    final created = await Process.run('mkfifo', <String>[
      path,
    ]).timeout(const Duration(seconds: 1));
    expect(created.exitCode, 0, reason: '${created.stderr}');
    final stopwatch = Stopwatch()..start();

    await expectLater(
      readWebReverseHarPath(path),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      readWebReverseHarFile(XFile(path)),
      throwsA(isA<FileSystemException>()),
    );

    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
  });

  test('reads an in-memory XFile through the bounded stream path', () async {
    final file = XFile.fromData(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      name: 'memory.har',
    );

    final result = await readWebReverseHarFile(file);

    expect(result.isTooLarge, isFalse);
    expect(result.bytes, orderedEquals(<int>[1, 2, 3, 4]));
  });
}
