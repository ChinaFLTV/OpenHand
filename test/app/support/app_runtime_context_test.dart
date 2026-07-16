import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/app_runtime_context.dart';

void main() {
  test('环境快照会安全归一化负数限制', () {
    final mergedEntryCount = <String, String>{
      ...Platform.environment,
      'ZZZ_OPENHAND_TEST_VALUE': 'value',
    }.length;

    final noEntries = AppRuntimeContext.captureEnvironmentSnapshot(
      const <String, String>{'ZZZ_OPENHAND_TEST_VALUE': 'value'},
      maxEntries: -1,
    );
    final noValueChars = AppRuntimeContext.captureEnvironmentSnapshot(
      const <String, String>{'ZZZ_OPENHAND_TEST_VALUE': 'value'},
      maxEntries: mergedEntryCount,
      maxValueChars: -1,
    );

    expect(noEntries, <String, String>{
      '_meta.truncated_keys': '$mergedEntryCount 个键已省略',
    });
    expect(noValueChars['ZZZ_OPENHAND_TEST_VALUE'], '…（已截断 5 个字符）');
  });

  test('环境快照使用统一中文脱敏和截断说明', () {
    final snapshot = AppRuntimeContext.captureEnvironmentSnapshot(
      const <String, String>{
        'ZZZ_OPENHAND_TEST_TOKEN': 'secret',
        'ZZZ_OPENHAND_TEST_VALUE': 'abcdef',
      },
      maxEntries: Platform.environment.length + 2,
      maxValueChars: 3,
    );

    expect(snapshot['ZZZ_OPENHAND_TEST_TOKEN'], '***已隐藏***');
    expect(snapshot['ZZZ_OPENHAND_TEST_VALUE'], 'abc…（已截断 3 个字符）');
    expect(snapshot['_meta.masked_keys'], isNotNull);
    expect(snapshot['_meta.masked_keys'], endsWith('个敏感值已隐藏'));
  });

  test('环境快照优先保留显式覆盖项并按字素安全截断', () {
    final prioritized = AppRuntimeContext.captureEnvironmentSnapshot(
      const <String, String>{'ZZZ_OPENHAND_TEST_VALUE': 'value'},
      maxEntries: 1,
    );
    final graphemeSafe = AppRuntimeContext.captureEnvironmentSnapshot(
      const <String, String>{'ZZZ_OPENHAND_TEST_VALUE': '👨‍👩‍👧‍👦A'},
      maxEntries: 1,
      maxValueChars: 1,
    );

    expect(prioritized['ZZZ_OPENHAND_TEST_VALUE'], 'value');
    expect(graphemeSafe['ZZZ_OPENHAND_TEST_VALUE'], '👨‍👩‍👧‍👦…（已截断 1 个字符）');
  });
}
