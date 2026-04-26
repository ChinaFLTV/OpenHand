import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/skills/data/skills_repository.dart';
import 'package:path/path.dart' as p;

const _skillManifest = '''---
name: Pdf Extract
description: Extract text from PDF files.
---

# Pdf Extract

Use it.
''';

void main() {
  group('SkillsRepository market archive install', () {
    late Directory tempDir;
    late SkillsRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'skills_repository_test_',
      );
      repository = SkillsRepository();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'strips a single archive root and installs SKILL.md at skill root',
      () async {
        final skill = await repository.installSkillArchive(
          tempDir.path,
          preferredSlug: 'pdf-extract',
          archiveBytes: _zipBytes(<String, String>{
            'pdf-extract/SKILL.md': _skillManifest,
            'pdf-extract/README.md': 'Read me.',
          }),
        );

        expect(skill.name, 'Pdf Extract');
        expect(skill.description, 'Extract text from PDF files.');
        expect(
          File(p.join(tempDir.path, 'pdf-extract', 'SKILL.md')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(tempDir.path, 'pdf-extract', 'README.md')).existsSync(),
          isTrue,
        );
      },
    );

    test(
      'rejects path traversal and removes the partial target directory',
      () async {
        await expectLater(
          () => repository.installSkillArchive(
            tempDir.path,
            preferredSlug: 'bad-skill',
            archiveBytes: _zipBytes(<String, String>{
              '../escape/SKILL.md': _skillManifest,
            }),
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(
          Directory(p.join(tempDir.path, 'bad-skill')).existsSync(),
          isFalse,
        );
        expect(
          Directory(p.join(tempDir.parent.path, 'escape')).existsSync(),
          isFalse,
        );
      },
    );
  });
}

Uint8List _zipBytes(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  return ZipEncoder().encodeBytes(archive);
}
