import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/app_restart_service.dart';

void main() {
  group('AppRestartService', () {
    test('resolves macOS app bundle from executable path', () {
      expect(
        AppRestartService.resolveMacOSAppBundle(
          '/Applications/OpenHand.app/Contents/MacOS/OpenHand',
        ),
        '/Applications/OpenHand.app',
      );
      expect(AppRestartService.resolveMacOSAppBundle('/tmp/OpenHand'), isNull);
    });

    test('prepares a cancellable macOS relaunch helper', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'openhand_restart_test_',
      );
      final starts = <_ProcessStartCall>[];
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final service = AppRestartService(
        executablePathProvider: () =>
            '/Applications/OpenHand.app/Contents/MacOS/OpenHand',
        tempDirectoryProvider: () => tempDir,
        processStarter:
            (
              executable,
              arguments, {
              mode = ProcessStartMode.normal,
              runInShell = false,
            }) async {
              starts.add(
                _ProcessStartCall(
                  executable: executable,
                  arguments: arguments,
                  mode: mode,
                  runInShell: runInShell,
                ),
              );
              return _FakeProcess();
            },
        exitApplication: (_, _) async => ui.AppExitResponse.exit,
        forceExit: (_) {},
        nowProvider: () => DateTime.fromMicrosecondsSinceEpoch(123456),
        pidProvider: () => 42,
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        relaunchDelay: Duration.zero,
      );

      final ticket = await service.prepareRelaunch();

      expect(starts, hasLength(1));
      expect(starts.single.executable, '/bin/sh');
      expect(starts.single.arguments, <String>[ticket.scriptPath]);
      expect(starts.single.mode, ProcessStartMode.detached);
      expect(starts.single.runInShell, isFalse);

      final script = File(ticket.scriptPath).readAsStringSync();
      expect(script, contains('/usr/bin/open -n -F --'));
      expect(script, contains("'/Applications/OpenHand.app'"));
      expect(script, contains('unset FLUTTER_ENGINE_SWITCHES'));
      expect(script, contains(r'unset "FLUTTER_ENGINE_SWITCH_$i"'));
      expect(script, isNot(contains(' -a ')));
      expect(File(ticket.pendingFlagPath).existsSync(), isTrue);

      await ticket.cancel();
      expect(File(ticket.pendingFlagPath).existsSync(), isFalse);
    });

    test('cancels relaunch ticket when app exit is canceled', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'openhand_restart_test_',
      );
      final forcedExitCodes = <int>[];
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final service = AppRestartService(
        executablePathProvider: () =>
            '/Applications/OpenHand.app/Contents/MacOS/OpenHand',
        tempDirectoryProvider: () => tempDir,
        processStarter:
            (
              executable,
              arguments, {
              mode = ProcessStartMode.normal,
              runInShell = false,
            }) async => _FakeProcess(),
        exitApplication: (_, _) async => ui.AppExitResponse.cancel,
        forceExit: forcedExitCodes.add,
        nowProvider: () => DateTime.fromMicrosecondsSinceEpoch(789012),
        pidProvider: () => 43,
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        relaunchDelay: Duration.zero,
      );
      final ticket = await service.prepareRelaunch();

      await expectLater(
        service.exitCurrentProcess(ticket: ticket),
        throwsA(
          isA<AppRestartException>().having(
            (error) => error.failure,
            'failure',
            AppRestartFailure.exitCanceled,
          ),
        ),
      );

      expect(File(ticket.pendingFlagPath).existsSync(), isFalse);
      expect(forcedExitCodes, isEmpty);
    });
  });
}

class _ProcessStartCall {
  const _ProcessStartCall({
    required this.executable,
    required this.arguments,
    required this.mode,
    required this.runInShell,
  });

  final String executable;
  final List<String> arguments;
  final ProcessStartMode mode;
  final bool runInShell;
}

class _FakeProcess implements Process {
  final _exitCodeCompleter = Completer<int>();

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  int get pid => 1234;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}
