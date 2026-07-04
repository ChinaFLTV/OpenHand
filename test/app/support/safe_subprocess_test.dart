import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/safe_subprocess.dart';

void main() {
  test('missing probe executables fail without debug stack noise', () async {
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() {
      debugPrint = previousDebugPrint;
    });

    final result = await runTrackedProcessOrFailed(
      '__openhand_missing_hermes_agent_probe__',
      const <String>['--version'],
      tag: 'plugin_lifecycle.verify.hermes-agent',
      timeout: const Duration(milliseconds: 500),
    );

    expect(result.exitCode, -1);
    expect(logs, isEmpty);
  });
}
