import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/home/message_path_linking.dart';

void main() {
  test(
    'messageFilePathRoots collects workspace and config parent directories',
    () {
      const environment = AiSessionEnvironment(
        localeTag: 'en',
        platform: 'macos',
        appVersion: '0.1.0',
        appBuildNumber: '1',
        applicationDirectory: '/workspace/app',
        homeDirectory: '/Users/demo',
        settingsFilePath: '/workspace/config/settings.toml',
        skillsStoragePath: '/workspace/skills',
        mcpServersFilePath: '/workspace/config/mcp_servers.json',
        userMemoryFilePath: '/workspace/data/memory.json',
        sessionsDirectoryPath: '/workspace/sessions',
        compressionThresholdChars: 5000,
      );

      final roots = messageFilePathRoots(
        environment,
        workingDirectory: '/workspace/run',
      );

      expect(roots.first, '/workspace/run');
      expect(roots, contains('/workspace/app'));
      expect(roots, contains('/Users/demo'));
      expect(roots, contains('/workspace/run'));
      expect(roots, contains('/workspace/skills'));
      expect(roots, contains('/workspace/sessions'));
      expect(roots, contains('/workspace/config'));
      expect(roots, contains('/workspace/data'));
    },
  );

  test(
    'resolveExistingMessagePath resolves bare relative and absolute paths',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'message-path-linking-resolve-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final relativeFile = File('${tempDirectory.path}/config-contract.md');
      final absoluteFile = File('${tempDirectory.path}/execution-rules.md');
      await relativeFile.writeAsString('# config');
      await absoluteFile.writeAsString('# rules');

      final resolvedRelative = resolveExistingMessagePath(
        'config-contract.md',
        [tempDirectory.path],
      );
      final resolvedAbsolute = resolveExistingMessagePath(absoluteFile.path, [
        '/unused/root',
      ]);

      expect(resolvedRelative, isNotNull);
      expect(resolvedRelative!.displayPath, 'config-contract.md');
      expect(resolvedRelative.resolvedPath, p.normalize(relativeFile.path));
      expect(resolvedRelative.isDirectory, isFalse);

      expect(resolvedAbsolute, isNotNull);
      expect(resolvedAbsolute!.displayPath, absoluteFile.path);
      expect(resolvedAbsolute.resolvedPath, p.normalize(absoluteFile.path));
      expect(resolvedAbsolute.isDirectory, isFalse);
    },
  );

  test(
    'resolveExistingMessagePath prefers working-directory roots and rechecks previously missing files',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'message-path-linking-priority-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final homeDirectory = Directory('${tempDirectory.path}/home');
      final workingDirectory = Directory('${tempDirectory.path}/working');
      await homeDirectory.create(recursive: true);
      await workingDirectory.create(recursive: true);

      final homeFile = File('${homeDirectory.path}/notes.md');
      final workingFile = File('${workingDirectory.path}/notes.md');
      await homeFile.writeAsString('# home');
      await workingFile.writeAsString('# working');

      final resolvedWorkingFile = resolveExistingMessagePath(
        'notes.md',
        <String>[workingDirectory.path, homeDirectory.path],
      );
      expect(resolvedWorkingFile, isNotNull);
      expect(resolvedWorkingFile!.resolvedPath, p.normalize(workingFile.path));

      final delayedFilePath = '${workingDirectory.path}/later.md';
      expect(
        resolveExistingMessagePath('later.md', <String>[workingDirectory.path]),
        isNull,
      );
      await File(delayedFilePath).writeAsString('# created later');

      final resolvedDelayedFile = resolveExistingMessagePath(
        'later.md',
        <String>[workingDirectory.path],
      );
      expect(resolvedDelayedFile, isNotNull);
      expect(resolvedDelayedFile!.resolvedPath, p.normalize(delayedFilePath));
    },
  );

  test(
    'resolveMarkdownMessageLinkPath and parseSupportedMessageLinkUri handle local and external links',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'message-path-linking-links-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final linkedFile = File('${tempDirectory.path}/quick_validate.py');
      await linkedFile.writeAsString('print("ok")');

      final fileUri = Uri.file(linkedFile.path).toString();
      final resolvedLink = resolveMarkdownMessageLinkPath(fileUri, [
        tempDirectory.path,
      ]);

      expect(resolvedLink, isNotNull);
      expect(resolvedLink!.resolvedPath, p.normalize(linkedFile.path));
      expect(
        parseSupportedMessageLinkUri('https://example.com/path'),
        isNotNull,
      );
      expect(
        parseSupportedMessageLinkUri('mailto:test@example.com'),
        isNotNull,
      );
      expect(parseSupportedMessageLinkUri(fileUri), isNotNull);
      expect(
        parseSupportedMessageLinkUri('ftp://example.com/file.txt'),
        isNull,
      );
    },
  );

  test(
    'MessageFilePathSyntax emits file nodes for existing paths and plain text for missing ones',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'message-path-linking-markdown-',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final existingFile = File('${tempDirectory.path}/config-contract.md');
      await existingFile.writeAsString('# config');

      final document = md.Document(
        inlineSyntaxes: <md.InlineSyntax>[
          MessageFilePathSyntax(candidateRoots: <String>[tempDirectory.path]),
        ],
      );
      final nodes = document.parseInline(
        'See config-contract.md and missing-file.txt for details.',
      );

      final fileNodes = nodes
          .whereType<md.Element>()
          .where((node) => node.tag == 'openhand-file')
          .toList(growable: false);
      final textContent = nodes
          .whereType<md.Text>()
          .map((node) => node.text)
          .join();

      expect(fileNodes, hasLength(1));
      expect(fileNodes.single.textContent, 'config-contract.md');
      expect(
        fileNodes.single.attributes['resolved_path'],
        p.normalize(existingFile.path),
      );
      expect(textContent, contains('missing-file.txt'));
      expect(textContent, contains('See'));
    },
  );
}
