import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/machine_terminal/index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('终端目录协议正确解析中文、链接并保持目录优先', () {
    String encoded(String value) => base64Encode(utf8.encode(value));
    final output = <String>[
      'P\t${encoded('/tmp/测试 目录')}',
      'E\tf\t12\t1700000000\t644\t${encoded('说明.txt')}\t',
      'E\td\t0\t1700000001\t755\t${encoded('子目录')}\t',
      'E\tl\t4\t1700000002\t777\t${encoded('最新')}\t${encoded('说明.txt')}',
      'T',
    ].join('\n');

    final snapshot = parseMachineTerminalDirectoryProtocol(
      output,
      windowsPath: false,
    );

    expect(snapshot.path, '/tmp/测试 目录');
    expect(snapshot.truncated, isTrue);
    expect(snapshot.entries.map((entry) => entry.name), <String>[
      '子目录',
      '最新',
      '说明.txt',
    ]);
    expect(snapshot.entries[1].linkTarget, '说明.txt');
  });

  test('文件详情协议保留路径、所有者和时间字段', () {
    String encoded(String value) => base64Encode(utf8.encode(value));
    final details = parseMachineTerminalFileDetailsProtocol(
      <String>[
        'D',
        'f',
        encoded('/tmp/测试.txt'),
        '12',
        '1700000000',
        '644',
        encoded('用户'),
        encoded('组'),
        '123',
        encoded('text/plain'),
        '',
        '1699990000',
        '1699991000',
        '1699992000',
      ].join('\t'),
      requestedPath: '/tmp/测试.txt',
    );

    expect(details.entry.path, '/tmp/测试.txt');
    expect(details.owner, '用户');
    expect(details.group, '组');
    expect(details.mimeType, 'text/plain');
    expect(details.createdAt, isNotNull);
  });

  test('批量上传校验失败时不残留部分任务', () async {
    final root = await Directory.systemTemp.createTemp(
      'openhand-terminal-upload-validation-',
    );
    final validFile = File('${root.path}/有效.txt');
    await validFile.writeAsString('content');
    final terminalService = MachineTerminalService();
    final fileService = MachineTerminalFileService(terminalService);
    try {
      await expectLater(
        fileService.enqueueUploads(
          sessionId: 'validation-test',
          terminalId: 'terminal-1',
          targetDirectory: '/tmp',
          sourcePaths: <String>[validFile.path, root.path],
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(fileService.transfers(), isEmpty);
    } finally {
      await fileService.shutdown();
      fileService.dispose();
      await terminalService.shutdown();
      terminalService.dispose();
      await root.delete(recursive: true);
    }
  });

  test(
    '终端文件服务跟随当前 PTY 路径并完成文件操作和分块上传',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'openhand-terminal-file-test-',
      );
      final sessions = await Directory.systemTemp.createTemp(
        'openhand-terminal-session-test-',
      );
      final child = await Directory('${root.path}/子目录').create();
      final source = File('${root.path}/本地上传.bin');
      final sourceBytes = List<int>.generate(140000, (index) => index % 251);
      await source.writeAsBytes(sourceBytes);
      await File('${child.path}/示例.txt').writeAsString('第一行\n第二行');

      final terminalService = MachineTerminalService(
        sessionsDirectoryPath: sessions.path,
      );
      final fileService = MachineTerminalFileService(terminalService);
      try {
        await terminalService.ensureWorkspace(
          sessionId: 'file-test',
          workingDirectory: child.path,
          start: false,
        );
        await terminalService.startTerminal(sessionId: 'file-test');
        final terminalId = terminalService
            .snapshot('file-test')!
            .activeTerminal!
            .terminalId;

        var directory = await fileService.listDirectory(
          sessionId: 'file-test',
          terminalId: terminalId,
        );
        expect(directory.path, await child.resolveSymbolicLinks());
        final textEntry = directory.entries.singleWhere(
          (entry) => entry.name == '示例.txt',
        );
        expect(
          await fileService.readTextFile(
            sessionId: 'file-test',
            terminalId: terminalId,
            entry: textEntry,
          ),
          '第一行\n第二行',
        );
        final details = await fileService.fileDetails(
          sessionId: 'file-test',
          terminalId: terminalId,
          path: textEntry.path,
        );
        expect(details.entry.size, greaterThan(0));

        await fileService.rename(
          sessionId: 'file-test',
          terminalId: terminalId,
          sourcePath: textEntry.path,
          newName: '已重命名.txt',
        );
        await fileService.copy(
          sessionId: 'file-test',
          terminalId: terminalId,
          sourcePath: '${child.path}/已重命名.txt',
          targetPath: '${child.path}/副本.txt',
        );
        await fileService.delete(
          sessionId: 'file-test',
          terminalId: terminalId,
          path: '${child.path}/已重命名.txt',
        );

        await fileService.enqueueUploads(
          sessionId: 'file-test',
          terminalId: terminalId,
          targetDirectory: child.path,
          sourcePaths: <String>[source.path],
        );
        await _waitForTransfer(fileService, terminalId);

        directory = await fileService.listDirectory(
          sessionId: 'file-test',
          terminalId: terminalId,
          path: child.path,
        );
        expect(
          directory.entries.map((entry) => entry.name),
          contains('副本.txt'),
        );
        expect(
          directory.entries.map((entry) => entry.name),
          isNot(contains('已重命名.txt')),
        );
        expect(await File('${child.path}/本地上传.bin').readAsBytes(), sourceBytes);
      } finally {
        await fileService.shutdown();
        fileService.dispose();
        await terminalService.shutdown();
        terminalService.dispose();
        await root.delete(recursive: true);
        await sessions.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: 'flutter test 不注入桌面 flutter_pty 动态库，需桌面构建环境执行。',
  );
}

Future<void> _waitForTransfer(
  MachineTerminalFileService service,
  String terminalId,
) async {
  final completer = Completer<void>();
  late final void Function() listener;
  listener = () {
    final tasks = service.transfers(terminalId: terminalId);
    if (tasks.isEmpty || tasks.any((task) => task.isActive)) return;
    service.removeListener(listener);
    final failed = tasks.where(
      (task) => task.status != MachineTerminalTransferStatus.completed,
    );
    if (failed.isEmpty) {
      completer.complete();
    } else {
      completer.completeError(StateError(failed.first.error ?? '文件传输失败。'));
    }
  };
  service.addListener(listener);
  listener();
  try {
    await completer.future.timeout(const Duration(seconds: 30));
  } finally {
    service.removeListener(listener);
  }
}
