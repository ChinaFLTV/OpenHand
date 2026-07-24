import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/android_reverse/android_reverse_adb_client.dart';
import 'package:openhand/features/android_reverse/android_reverse_session_config.dart';
import 'package:openhand/features/android_reverse/android_reverse_session_controller.dart';

void main() {
  group('AndroidReverseSessionController', () {
    test('设备刷新期间的新请求会合并为一次补偿刷新', () async {
      final adbClient = _ControlledAdbClient();
      final controller = _createController(adbClient);
      addTearDown(controller.dispose);

      final first = controller.refreshDevices();
      final second = controller.refreshDevices();
      expect(adbClient.deviceRequests, hasLength(1));

      adbClient.deviceRequests.first.complete(const <AdbDevice>[]);
      await _waitFor(() => adbClient.deviceRequests.length == 2);
      var completed = false;
      second.whenComplete(() => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      adbClient.deviceRequests.last.complete(const <AdbDevice>[]);
      await Future.wait(<Future<List<AdbDevice>>>[first, second]);
      expect(completed, isTrue);
      expect(adbClient.deviceRequests, hasLength(2));
    });

    test('较早完成的进程刷新不会覆盖较新的结果', () async {
      final adbClient = _ControlledAdbClient();
      final controller = _createController(adbClient);
      addTearDown(controller.dispose);

      final older = controller.refreshProcesses(filterName: 'older');
      final newer = controller.refreshProcesses(filterName: 'newer');
      final oldRequest = adbClient.processRequests[0];
      final newRequest = adbClient.processRequests[1];
      const oldProcesses = <AndroidProcess>[
        AndroidProcess(pid: 1, name: 'older'),
      ];
      const newProcesses = <AndroidProcess>[
        AndroidProcess(pid: 2, name: 'newer'),
      ];

      newRequest.completer.complete(newProcesses);
      await newer;
      oldRequest.completer.complete(oldProcesses);
      await older;

      expect(controller.processes, same(newProcesses));
    });

    test('最新进程刷新失败时清除旧缓存', () async {
      final adbClient = _ControlledAdbClient();
      final controller = _createController(adbClient);
      addTearDown(controller.dispose);
      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {};
      addTearDown(() => debugPrint = originalDebugPrint);

      final initial = controller.refreshProcesses(filterName: 'initial');
      adbClient.processRequests.single.completer.complete(
        const <AndroidProcess>[AndroidProcess(pid: 1, name: 'initial')],
      );
      await initial;
      expect(controller.processes, isNotEmpty);

      final failed = controller.refreshProcesses(filterName: 'failed');
      adbClient.processRequests.last.completer.completeError(
        StateError('模拟刷新失败'),
      );

      expect(await failed, isEmpty);
      expect(controller.processes, isEmpty);
    });
  });
}

AndroidReverseSessionController _createController(
  AndroidReverseAdbClient adbClient,
) {
  return AndroidReverseSessionController(
    config: const AndroidReverseSessionConfig(objective: '测试'),
    artifactsRootDir: '/tmp/openhand_android_reverse_test',
    adbClient: adbClient,
  );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('等待条件超时');
}

class _ControlledAdbClient extends AndroidReverseAdbClient {
  final List<Completer<List<AdbDevice>>> deviceRequests =
      <Completer<List<AdbDevice>>>[];
  final List<({String? filter, Completer<List<AndroidProcess>> completer})>
  processRequests =
      <({String? filter, Completer<List<AndroidProcess>> completer})>[];

  @override
  Future<List<AdbDevice>> listDevices() {
    final completer = Completer<List<AdbDevice>>();
    deviceRequests.add(completer);
    return completer.future;
  }

  @override
  Future<List<AndroidProcess>> listProcesses({String? filterName}) {
    final completer = Completer<List<AndroidProcess>>();
    processRequests.add((filter: filterName, completer: completer));
    return completer.future;
  }
}
