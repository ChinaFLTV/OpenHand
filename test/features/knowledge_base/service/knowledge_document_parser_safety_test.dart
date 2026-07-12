import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipEncoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_document_parser.dart';
import 'package:openhand/shared/db/atomic_file_operations.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_knowledge_parser_safety_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('parser rejects a document larger than the configured limit', () async {
    final file = File('${tempDirectory.path}/oversized.txt');
    final handle = await file.open(mode: FileMode.write);
    await handle.setPosition(1024 * 1024);
    await handle.writeByte(0);
    await handle.close();

    final request = KnowledgeDocumentParseRequest(
      file: file,
      settings: const KnowledgeBaseSettings(maxFileSizeMb: 1),
      stat: await file.stat(),
    );

    await expectLater(
      const KnowledgeDocumentParserRegistry().parse(request),
      throwsA(isA<StateError>()),
    );
  });

  test('persisted file size limits normalize to the parser hard cap', () {
    final settings = KnowledgeBaseSettings.fromJson(const <String, Object?>{
      'max_file_size_mb': 10240,
    });

    expect(settings.maxFileSizeMb, 256);
  });

  test('direct settings cannot bypass the parser hard cap', () async {
    final file = File('${tempDirectory.path}/hard-cap.txt');
    final handle = await file.open(mode: FileMode.write);
    await handle.setPosition(256 * 1024 * 1024);
    await handle.writeByte(0);
    await handle.close();
    final request = KnowledgeDocumentParseRequest(
      file: file,
      settings: const KnowledgeBaseSettings(maxFileSizeMb: 10240),
      stat: await file.stat(),
    );

    await expectLater(
      const KnowledgeDocumentParserRegistry().parse(request),
      throwsA(isA<StateError>()),
    );
  });

  test('parser rejects oversized XML metadata before expanding it', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes('word/document.xml', Uint8List(32 * 1024 * 1024 + 1)),
      );
    final encoded = ZipEncoder().encode(archive);
    final file = File('${tempDirectory.path}/oversized.docx');
    await file.writeAsBytes(encoded);

    final request = KnowledgeDocumentParseRequest(
      file: file,
      settings: const KnowledgeBaseSettings(maxFileSizeMb: 1),
      stat: await file.stat(),
    );

    await expectLater(
      const KnowledgeDocumentParserRegistry().parse(request),
      throwsA(isA<FormatException>()),
    );
  });

  test('parser bounds flate-expanded PDF streams', () async {
    final expanded = Uint8List(16 * 1024 * 1024 + 1);
    final compressed = ZLibEncoder().convert(expanded);
    final file = File('${tempDirectory.path}/oversized.pdf');
    await file.writeAsBytes(<int>[
      ...latin1.encode('%PDF-1.7\n<< /Filter /FlateDecode >>\nstream\n'),
      ...compressed,
      ...latin1.encode('\nendstream\n%%EOF'),
    ]);

    final request = KnowledgeDocumentParseRequest(
      file: file,
      settings: const KnowledgeBaseSettings(maxFileSizeMb: 1),
      stat: await file.stat(),
    );

    await expectLater(
      const KnowledgeDocumentParserRegistry().parse(request),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('PDF 解压文本流大小超过安全上限'),
        ),
      ),
    );
  });

  test(
    'atomic file copy enforces limits without publishing a target',
    () async {
      final source = File('${tempDirectory.path}/source.bin');
      await source.writeAsBytes(const <int>[1, 2, 3, 4]);
      final target = File('${tempDirectory.path}/target.bin');

      await expectLater(
        copyFileAtomically(source, target, maxBytes: 3),
        throwsA(isA<FileSystemException>()),
      );

      expect(await target.exists(), isFalse);
      final leftovers = await tempDirectory
          .list()
          .where((entity) => entity.path.contains('target.bin.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    },
  );

  test('atomic file copy rejects a FIFO before blocking open', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final sourcePath = '${tempDirectory.path}/source.fifo';
    final created = await Process.run('mkfifo', <String>[
      sourcePath,
    ]).timeout(const Duration(seconds: 1));
    expect(created.exitCode, 0, reason: '${created.stderr}');
    final target = File('${tempDirectory.path}/target.bin');
    final stopwatch = Stopwatch()..start();

    await expectLater(
      copyFileAtomically(File(sourcePath), target, maxBytes: 1024),
      throwsA(isA<FileSystemException>()),
    );
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
    expect(await target.exists(), isFalse);
  });

  test('atomic text writes preserve Unicode at a chunk boundary', () async {
    const chunkBoundary = 64 * 1024;
    final target = File('${tempDirectory.path}/unicode.txt');
    await target.writeAsString('previous');
    final content =
        '${List<String>.filled(chunkBoundary - 1, 'a').join()}'
        '😃tail';

    await writeFileAtomically(target, content);

    expect(await target.readAsString(), content);
    expect(await File('${target.path}.bak').exists(), isFalse);
  });

  test('atomic byte writes preserve data across chunk boundaries', () async {
    const chunkBoundary = 64 * 1024;
    final target = File('${tempDirectory.path}/bytes.bin');
    final bytes = Uint8List.fromList(
      List<int>.generate(chunkBoundary + 17, (index) => index & 0xFF),
    );

    await writeFileBytesAtomically(target, bytes);

    expect(await target.readAsBytes(), orderedEquals(bytes));
  });

  test('atomic byte writes snapshot caller-owned mutable data', () async {
    final target = File('${tempDirectory.path}/snapshot.bin');
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

    final write = writeFileBytesAtomically(target, bytes);
    bytes.fillRange(0, bytes.length, 9);
    await write;

    expect(await target.readAsBytes(), orderedEquals(const <int>[1, 2, 3, 4]));
  });

  test('atomic file copy publishes a stable source exactly once', () async {
    final source = File('${tempDirectory.path}/stable-source.bin');
    final target = File('${tempDirectory.path}/stable-target.bin');
    final bytes = Uint8List.fromList(
      List<int>.generate(128 * 1024 + 3, (index) => index & 0xFF),
    );
    await source.writeAsBytes(bytes);

    await copyFileAtomically(source, target, maxBytes: bytes.length);

    expect(await target.readAsBytes(), orderedEquals(bytes));
  });

  test('atomic recovery never publishes an incomplete working file', () async {
    final target = File('${tempDirectory.path}/recover.json');
    final backup = File('${target.path}.bak');
    final incomplete = File('${target.path}.tmp.writing.interrupted');
    await backup.writeAsString('previous');
    await incomplete.writeAsString('partial');

    await recoverAtomicWriteBackupIfNeeded(target);

    expect(await target.readAsString(), 'previous');
  });

  test('bounded parser still accepts a normal markdown document', () async {
    final file = File('${tempDirectory.path}/notes.md');
    await file.writeAsString('# Notes\n\nSafe content.');
    final request = KnowledgeDocumentParseRequest(
      file: file,
      settings: const KnowledgeBaseSettings(maxFileSizeMb: 1),
      stat: await file.stat(),
    );

    final result = await const KnowledgeDocumentParserRegistry().parse(request);

    expect(result.kind, 'markdown');
    expect(result.text, contains('Safe content.'));
  });
}
