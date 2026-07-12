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
