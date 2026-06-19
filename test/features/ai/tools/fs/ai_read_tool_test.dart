import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/fs/ai_file_tracker_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/ai_tool_utils.dart';
import 'package:openhand/features/ai/tools/fs/ai_read_tool.dart';

void main() {
  group('AiReadTool', () {
    test('resolves relative file paths from the working directory', () async {
      final originalWorkingDirectory = Directory.current.path;
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        Directory.current = originalWorkingDirectory;
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      Directory.current = tempDir.path;

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\nbeta\n');

      final result = await AiReadTool().execute(
        _context(
          id: 'read-relative-path',
          filePath: 'sample.txt',
          offset: 1,
          limit: 2,
          fileTracker: AiFileTrackerService(),
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains('   1\talpha'));
      expect(result.metadata['read_file_path'], endsWith('/sample.txt'));
    });

    test('rejects special device paths before filesystem reading', () async {
      for (final path in <String>['/dev/zero', '/proc/self/fd/0']) {
        final result = await AiReadTool().execute(
          _context(
            id: 'read-blocked-device-$path',
            filePath: path,
            offset: 1,
            limit: 2,
            fileTracker: AiFileTrackerService(),
          ),
        );

        expect(result.status.storageValue, 'invalid_arguments');
        expect(result.stderr, contains('special device path'));
        expect(result.stderr, isNot(contains('File does not exist')));
      }
    });

    test('suggests a similar sibling path when file is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sibling = File('${tempDir.path}/sample.txt');
      await sibling.writeAsString('alpha\n');
      final missingPath = '${tempDir.path}/sample.dart';

      final result = await AiReadTool().execute(
        _context(
          id: 'read-missing-suggestion',
          filePath: missingPath,
          offset: 1,
          limit: 2,
          fileTracker: AiFileTrackerService(),
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('File does not exist: $missingPath'));
      expect(result.stderr, contains('Did you mean ${sibling.path}?'));
    });

    test('resolves macOS screenshot thin-space AM PM path variants', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final actualPath =
          '${tempDir.path}/Screenshot 2026-06-20 at 10.15.30\u202fAM.png';
      final requestedPath =
          '${tempDir.path}/Screenshot 2026-06-20 at 10.15.30 AM.png';
      await File(
        actualPath,
      ).writeAsBytes(<int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

      final result = await AiReadTool().execute(
        _context(
          id: 'read-screenshot-thin-space',
          filePath: requestedPath,
          offset: 1,
          limit: 2,
          fileTracker: AiFileTrackerService(),
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.metadata['read_file_path'], actualPath);
      expect(result.metadata['read_file_requested_path'], requestedPath);
      expect(result.metadata['read_file_alternate_path_used'], true);
      expect(result.stdout, contains('file_type: image'));
    });

    test('returns metadata only for oversized structured files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final cases = <({String name, String fileType, String? pages})>[
        (name: 'large.png', fileType: 'image', pages: null),
        (name: 'large.pdf', fileType: 'pdf', pages: '1-2'),
        (name: 'large.ipynb', fileType: 'notebook', pages: null),
      ];

      for (final item in cases) {
        final file = File('${tempDir.path}/${item.name}');
        final handle = await file.open(mode: FileMode.write);
        try {
          await handle.truncate(AiToolUtils.maxStructuredReadBytes + 1);
        } finally {
          await handle.close();
        }

        final result = await AiReadTool().execute(
          _context(
            id: 'read-oversized-${item.name}',
            filePath: file.path,
            offset: 1,
            limit: 2,
            fileTracker: AiFileTrackerService(),
            pages: item.pages,
          ),
        );

        expect(result.status.storageValue, 'success');
        expect(result.stdout, contains('file_type: ${item.fileType}'));
        expect(
          result.stdout,
          contains('size_limit_bytes: ${AiToolUtils.maxStructuredReadBytes}'),
        );
        expect(result.stdout, contains('Full structured rendering is skipped'));
        expect(result.metadata['read_truncated'], isTrue);
        if (item.pages != null) {
          expect(result.stdout, contains('requested_pages: ${item.pages}'));
        }
      }
    });

    test('offset is interpreted as a 1-based starting line', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\nbeta\ngamma\ndelta\n');

      final result = await AiReadTool().execute(
        AiToolExecutionContext(
          sessionId: 'test-session',
          catalog: const AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[],
            toolsByName: <String, AiResolvedTool>{},
          ),
          toolCall: AiToolCall(
            id: 'read-offset',
            name: 'Read',
            arguments: jsonEncode(<String, Object?>{
              'file_path': file.path,
              'offset': 2,
              'limit': 2,
            }),
          ),
          decodedArguments: <String, Object?>{
            'file_path': file.path,
            'offset': 2,
            'limit': 2,
          },
          model: _testModel,
          previouslyReadFiles: <String>{},
          denyCommandRules: const <Never>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: null,
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains('   2\tbeta'));
      expect(result.stdout, contains('   3\tgamma'));
      expect(result.stdout, isNot(contains('alpha')));
      expect(result.stdout, isNot(contains('delta')));
    });

    test('offset can read beyond the initial large-file prefix', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/large.txt');
      final buffer = StringBuffer();
      final padding = ''.padRight(80, 'x');
      for (var i = 1; i <= 9000; i++) {
        buffer.writeln('line-${i.toString().padLeft(4, '0')} $padding');
      }
      await file.writeAsString(buffer.toString());

      final result = await AiReadTool().execute(
        _context(
          id: 'read-large-offset',
          filePath: file.path,
          offset: 8500,
          limit: 3,
          fileTracker: AiFileTrackerService(),
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains('8500\tline-8500'));
      expect(result.stdout, contains('8502\tline-8502'));
      expect(result.stdout, isNot(contains('line-0001')));
      expect(result.metadata['read_truncated'], isTrue);
    });

    test('offset beyond end reports empty range, not empty file', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\nbeta\n');

      final result = await AiReadTool().execute(
        _context(
          id: 'read-offset-beyond-end',
          filePath: file.path,
          offset: 20,
          limit: 3,
          fileTracker: AiFileTrackerService(),
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, 'No lines available in the requested range.');
      expect(result.stdout, isNot(contains('File is empty')));
    });

    test('returns unchanged stub for repeated same-range reads', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\nbeta\ngamma\n');
      final tracker = AiFileTrackerService();
      final tool = AiReadTool();

      final first = await tool.execute(
        _context(
          id: 'read-first',
          filePath: file.path,
          offset: 1,
          limit: 2,
          fileTracker: tracker,
        ),
      );
      final second = await tool.execute(
        _context(
          id: 'read-second',
          filePath: file.path,
          offset: 1,
          limit: 2,
          fileTracker: tracker,
        ),
      );

      expect(first.status.storageValue, 'success');
      expect(first.stdout, contains('alpha'));
      expect(second.status.storageValue, 'success');
      expect(second.stdout, contains('File unchanged since last read'));
      expect(second.stdout, isNot(contains('alpha')));
      expect(second.metadata['read_file_unchanged'], isTrue);
    });

    test('re-reads content after same-range file changes', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\nbeta\n');
      final tracker = AiFileTrackerService();
      final tool = AiReadTool();

      await tool.execute(
        _context(
          id: 'read-before-change',
          filePath: file.path,
          offset: 1,
          limit: 2,
          fileTracker: tracker,
        ),
      );
      await file.writeAsString('delta\nepsilon\n');

      final result = await tool.execute(
        _context(
          id: 'read-after-change',
          filePath: file.path,
          offset: 1,
          limit: 2,
          fileTracker: tracker,
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains('delta'));
      expect(result.stdout, isNot(contains('File unchanged since last read')));
    });

    test('accepts Claude-style PDF pages range as explicit metadata', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.pdf');
      await file.writeAsString(
        '%PDF-1.4\n'
        '1 0 obj << /Type /Page >> endobj\n'
        '2 0 obj << /Type /Page >> endobj\n',
        encoding: latin1,
      );

      final result = await AiReadTool().execute(
        _context(
          id: 'read-pdf-pages',
          filePath: file.path,
          offset: 1,
          limit: 10,
          fileTracker: AiFileTrackerService(),
          pages: '1-2',
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains('file_type: pdf'));
      expect(result.stdout, contains('requested_pages: 1-2'));
      expect(result.stdout, contains('requested_page_count: 2'));
      expect(
        result.stdout,
        contains('Page-range text extraction is not available'),
      );
    });

    test('rejects pages for non-PDF files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');

      final result = await AiReadTool().execute(
        _context(
          id: 'read-text-pages',
          filePath: file.path,
          offset: 1,
          limit: 10,
          fileTracker: AiFileTrackerService(),
          pages: '1',
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('only supported for PDF'));
    });

    test('rejects PDF page ranges over the Claude-compatible cap', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.pdf');
      await file.writeAsString('%PDF-1.4\n', encoding: latin1);

      final result = await AiReadTool().execute(
        _context(
          id: 'read-pdf-too-many-pages',
          filePath: file.path,
          offset: 1,
          limit: 10,
          fileTracker: AiFileTrackerService(),
          pages: '1-21',
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('at most 20 PDF pages'));
    });
  });
}

AiToolExecutionContext _context({
  required String id,
  required String filePath,
  required int offset,
  required int limit,
  required AiFileTrackerService fileTracker,
  String? pages,
}) {
  final arguments = <String, Object?>{
    'file_path': filePath,
    'offset': offset,
    'limit': limit,
    if (pages != null) 'pages': pages,
  };
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: id,
      name: 'Read',
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _testModel,
    previouslyReadFiles: <String>{},
    denyCommandRules: const <Never>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
    metadata: <String, Object?>{'file_tracker': fileTracker},
  );
}

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);
