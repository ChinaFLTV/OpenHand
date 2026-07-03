import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/app_restart_service.dart';

void main() {
  group('AppRestartService', () {
    test('rejects blank executable paths before normalizing', () async {
      final service = AppRestartService(
        executablePathProvider: () => '   ',
        tempDirectoryProvider: () => Directory.systemTemp,
        processStarter:
            (
              executable,
              arguments, {
              mode = ProcessStartMode.normal,
              runInShell = false,
            }) => throw StateError('processStarter should not be called'),
        exitApplication: (_, _) async => ui.AppExitResponse.exit,
        forceExit: (_) {},
      );

      await expectLater(
        service.prepareRelaunch(),
        throwsA(
          isA<AppRestartException>().having(
            (error) => error.failure,
            'failure',
            AppRestartFailure.missingExecutable,
          ),
        ),
      );
    });
  });
}
