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
      'E\td\t0\t1700000001\t755\t${encoded('子目录')}\t\t2\t3',
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
    expect(snapshot.entries.first.childDirectoryCount, 2);
    expect(snapshot.entries.first.childFileCount, 3);
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
        '0',
        '0',
      ].join('\t'),
      requestedPath: '/tmp/测试.txt',
    );

    expect(details.entry.path, '/tmp/测试.txt');
    expect(details.owner, '用户');
    expect(details.group, '组');
    expect(details.mimeType, 'text/plain');
    expect(details.createdAt, isNotNull);
  });

  test('远端临时路径协议忽略 relay 提示符和命令回显', () {
    const path = '/var/tmp/relay path/openhand-command.Ab12xy';
    final encoded = base64Encode(utf8.encode(path));
    final output = <String>[
      r'''[root@relay ~]# printf "__OPENHAND_STAGED_PATH_BEGIN__%s__OPENHAND_STAGED_PATH_END__\n" "$__oh_tmp"''',
      '> > __OPENHAND_STAGED_PATH_BEGIN__$encoded'
          '__OPENHAND_STAGED_PATH_END__',
      '[root@relay ~]#',
    ].join('\n');

    expect(parseMachineTerminalStagedPathProtocol(output), path);
  });

  test('远端临时路径协议拒绝伪造和越界路径', () {
    for (final path in <String>[
      '/tmp/openhand-command.Ab12xy/越界',
      '/tmp/../etc/openhand-command.Ab12xy',
    ]) {
      final encoded = base64Encode(utf8.encode(path));
      final output =
          '__OPENHAND_STAGED_PATH_BEGIN__$encoded'
          '__OPENHAND_STAGED_PATH_END__';
      expect(
        () => parseMachineTerminalStagedPathProtocol(output),
        throwsStateError,
      );
    }
  });

  test('文件管理命令不写入关联终端历史', () async {
    final sessions = await Directory.systemTemp.createTemp(
      'openhand-terminal-history-policy-',
    );
    final terminalService = MachineTerminalService(
      sessionsDirectoryPath: sessions.path,
    );
    try {
      final workspace = await terminalService.ensureWorkspace(
        sessionId: 'history-policy-test',
        start: false,
      );
      final terminalId = workspace.activeTerminal!.terminalId;

      await terminalService.executeCommand(
        sessionId: 'history-policy-test',
        terminalId: terminalId,
        command: 'pwd',
        startIfNeeded: false,
        recordHistory: false,
      );

      final snapshot = terminalService.snapshot('history-policy-test')!;
      expect(snapshot.activeTerminal!.commandCount, 0);
      expect(snapshot.activeTerminal!.commandHistory, isEmpty);
      expect(snapshot.activeTerminal!.hasUserActivity, isFalse);

      await terminalService.executeCommand(
        sessionId: 'history-policy-test',
        terminalId: terminalId,
        command: 'whoami',
        startIfNeeded: false,
      );

      final recorded = terminalService.snapshot('history-policy-test')!;
      expect(recorded.activeTerminal!.commandCount, 1);
      expect(recorded.activeTerminal!.commandHistory.single.command, 'whoami');
      expect(recorded.activeTerminal!.hasUserActivity, isTrue);
    } finally {
      await terminalService.shutdown();
      terminalService.dispose();
      await sessions.delete(recursive: true);
    }
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

  test('传输记录明确区分上传与下载任务', () async {
    final root = await Directory.systemTemp.createTemp(
      'openhand-terminal-transfer-direction-',
    );
    final source = File('${root.path}/上传.txt');
    await source.writeAsString('content');
    final terminalService = MachineTerminalService();
    final fileService = MachineTerminalFileService(terminalService);
    try {
      await fileService.enqueueUploads(
        sessionId: 'direction-test',
        terminalId: 'terminal-1',
        targetDirectory: '/tmp',
        sourcePaths: <String>[source.path],
      );
      fileService.enqueueDownload(
        sessionId: 'direction-test',
        terminalId: 'terminal-1',
        sourcePath: '/tmp/下载.txt',
        destinationPath: '${root.path}/下载.txt',
        totalBytes: 12,
      );

      expect(
        fileService.transfers().map((task) => task.direction),
        <MachineTerminalTransferDirection>[
          MachineTerminalTransferDirection.upload,
          MachineTerminalTransferDirection.download,
        ],
      );
    } finally {
      await fileService.shutdown();
      fileService.dispose();
      await terminalService.shutdown();
      terminalService.dispose();
      await root.delete(recursive: true);
    }
  });

  test('文件传输记录在应用重启后仍可恢复', () async {
    final sessions = await Directory.systemTemp.createTemp(
      'openhand-terminal-transfer-history-',
    );
    final firstTerminalService = MachineTerminalService(
      sessionsDirectoryPath: sessions.path,
    );
    final firstFileService = MachineTerminalFileService(firstTerminalService);
    try {
      final taskId = firstFileService.enqueueDownload(
        sessionId: 'transfer-history-session',
        terminalId: 'transfer-history-terminal',
        sourcePath: '/remote/报告.zip',
        destinationPath: '${sessions.path}/报告.zip',
        totalBytes: 4096,
      );
      firstFileService.cancelTransfer(taskId);
      await firstFileService.shutdown();

      final secondTerminalService = MachineTerminalService(
        sessionsDirectoryPath: sessions.path,
      );
      final secondFileService = MachineTerminalFileService(
        secondTerminalService,
      );
      try {
        await secondFileService.transferHistoryReady;
        final restored = secondFileService.transfers(
          sessionId: 'transfer-history-session',
          terminalId: 'transfer-history-terminal',
        );

        expect(restored, hasLength(1));
        expect(restored.single.id, taskId);
        expect(
          restored.single.direction,
          MachineTerminalTransferDirection.download,
        );
        expect(restored.single.sourcePath, '/remote/报告.zip');
        expect(restored.single.totalBytes, 4096);
        expect(restored.single.status, MachineTerminalTransferStatus.canceled);
      } finally {
        await secondFileService.shutdown();
        secondFileService.dispose();
        await secondTerminalService.shutdown();
        secondTerminalService.dispose();
      }
    } finally {
      firstFileService.dispose();
      await firstTerminalService.shutdown();
      firstTerminalService.dispose();
      await sessions.delete(recursive: true);
    }
  });

  test('文件传输服务关闭任务可安全复用并拒绝新任务', () async {
    final sessions = await Directory.systemTemp.createTemp(
      'openhand-terminal-file-shutdown-',
    );
    final terminalService = MachineTerminalService(
      sessionsDirectoryPath: sessions.path,
    );
    final fileService = MachineTerminalFileService(terminalService);
    try {
      final firstShutdown = fileService.shutdown();
      final secondShutdown = fileService.shutdown();

      expect(identical(firstShutdown, secondShutdown), isTrue);
      expect(
        () => fileService.enqueueDownload(
          sessionId: 'shutdown-session',
          terminalId: 'shutdown-terminal',
          sourcePath: '/remote/file.bin',
          destinationPath: '${sessions.path}/file.bin',
          totalBytes: 1,
        ),
        throwsStateError,
      );
      await firstShutdown;
    } finally {
      fileService.dispose();
      await terminalService.shutdown();
      terminalService.dispose();
      await sessions.delete(recursive: true);
    }
  });

  test('文件传输记录持久化失败不会泄漏未处理异步异常', () async {
    final root = await Directory.systemTemp.createTemp(
      'openhand-terminal-transfer-persist-error-',
    );
    final blockedSessionsPath = '${root.path}/not-a-directory';
    await File(blockedSessionsPath).writeAsString('blocked');
    final uncaughtErrors = <Object>[];

    await runZonedGuarded(() async {
      final terminalService = MachineTerminalService(
        sessionsDirectoryPath: blockedSessionsPath,
      );
      final fileService = MachineTerminalFileService(terminalService);
      try {
        await fileService.transferHistoryReady;
        final taskId = fileService.enqueueDownload(
          sessionId: 'persist-error-session',
          terminalId: 'persist-error-terminal',
          sourcePath: '/remote/file.bin',
          destinationPath: '${root.path}/file.bin',
          totalBytes: 1,
        );
        fileService.cancelTransfer(taskId);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await fileService.shutdown();
      } finally {
        fileService.dispose();
        await terminalService.shutdown();
        terminalService.dispose();
      }
    }, (error, _) => uncaughtErrors.add(error));

    expect(uncaughtErrors, isEmpty);
    await root.delete(recursive: true);
  });

  test('传输记录提供真实进度速度耗时和剩余时间', () {
    final startedAt = DateTime.now().subtract(const Duration(seconds: 4));
    final task = MachineTerminalTransferTask(
      id: 'stats-test',
      sessionId: 'session',
      terminalId: 'terminal',
      direction: MachineTerminalTransferDirection.upload,
      sourcePath: '/tmp/source.bin',
      targetDirectory: '/tmp',
      fileName: 'source.bin',
      totalBytes: 4096,
      transferredBytes: 2048,
      status: MachineTerminalTransferStatus.transferring,
      createdAt: startedAt,
      startedAt: startedAt,
      speedBytesPerSecond: 1024,
    );

    expect(task.progress, closeTo(0.5, 0.0001));
    expect(task.effectiveSpeedBytesPerSecond, 1024);
    expect(task.elapsed.inSeconds, greaterThanOrEqualTo(4));
    expect(task.estimatedRemaining?.inSeconds, greaterThanOrEqualTo(1));
  });

  test('文件操作进度仅在总字节明确时提供真实百分比', () {
    const waiting = MachineTerminalFileProgress(command: 'pwd');
    const reading = MachineTerminalFileProgress(
      command: '读取文件分块',
      processedBytes: 32768,
      totalBytes: 65536,
    );
    const overflow = MachineTerminalFileProgress(
      command: '读取文件分块',
      processedBytes: 70000,
      totalBytes: 65536,
    );

    expect(waiting.progress, isNull);
    expect(reading.progress, closeTo(0.5, 0.0001));
    expect(overflow.progress, 1);
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
        expect(
          fileService.transfers().first.direction,
          MachineTerminalTransferDirection.upload,
        );

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
        final downloaded = File('${sessions.path}/终端下载.bin');
        await downloaded.writeAsString('旧内容');
        fileService.enqueueDownload(
          sessionId: 'file-test',
          terminalId: terminalId,
          sourcePath: '${child.path}/本地上传.bin',
          destinationPath: downloaded.path,
          totalBytes: sourceBytes.length,
        );
        await _waitForTransfer(fileService, terminalId);
        expect(await downloaded.readAsBytes(), sourceBytes);
        expect(
          fileService.transfers().last.direction,
          MachineTerminalTransferDirection.download,
        );
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
