import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance_timestamp.dart';
import 'package:openhand/shared/util/date_time_format.dart';

void main() {
  void check(String raw, String? expected, {bool allowEpoch = false}) {
    final actual = machineMaintenanceTimestamp(raw, allowEpoch: allowEpoch);
    if (actual != expected) {
      throw StateError('日期格式化失败：$raw → $actual，预期 $expected');
    }
  }

  for (final raw in [
    '2026-08-18 18:01:59 +0800 CST',
    '2026-08-18T18:01:59.123456789+08:00',
    '2026-08-18T18:01:59Z',
    '2026-08-18T18:01:59-07:00',
    'Tue 2026-08-18 18:01:59 CST',
    'Tue Aug 18 18:01:59 2026',
    'Tue Aug 18 18:01:59 CST 2026',
    '20260818180159.000000+480',
    '20260818180159.000000-420',
    ' 2026-08-18 18:01:59 ',
  ]) {
    check(raw, '2026-08-18 18:01:59');
  }
  check('2026-08-18 18:01', '2026-08-18 18:01:00');
  check('Tue Sep 29 19:22 2026', '2026-09-29 19:22:00');
  check('Sep 29 19:22', '${DateTime.now().year}-09-29 19:22:00');
  check('2026-9-8-1:2:3', '2026-09-08 01:02:03');
  check('2026-09-30', '2026-09-30 00:00:00');
  check('2024-02-29T23:59:59.999Z', '2024-02-29 23:59:59');
  check('2026-12-31T23:59:59-12:00', '2026-12-31 23:59:59');
  check('2026-01-01T00:00:00+14:00', '2026-01-01 00:00:00');
  for (final raw in [
    '',
    '—',
    'n/a',
    'never',
    '0',
    'infinity',
    '0000-00-00T00:00:00Z',
    '2026-02-29 12:00:00',
    '2026-02-30 12:00:00',
    '2026-13-01 12:00:00',
    '2026-12-01 24:00:00',
    '2026-12-01 12:60:00',
    '2026-12-01 12:00:60',
    '2026-12-01 12:00:00+24:00',
    '2026-12-01 12:00:00+08:60',
    '20260230120000.000000+480',
    'Foo 29 12:00:00 2026',
    'Feb 30 12:00:00 2026',
    '累计 2026-08-18 18:01:59',
    '2026-08-18 18:01:59 broken',
    '18:01:59',
    '2-03:04:05',
    '120000000000',
    '10.0.0.1',
  ]) {
    check(raw, null, allowEpoch: true);
  }

  const seconds = 1787047319;
  final epochExpected = formatListDateTime(
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
  );
  for (final raw in [
    '$seconds',
    '${seconds}999',
    '${seconds}999999',
    '${seconds}999999999',
  ]) {
    check(raw, null);
    check(raw, epochExpected, allowEpoch: true);
  }

  for (final field in [
    '创建时间',
    'State / StartedAt',
    'metadata / creationTimestamp',
    'LastBootUpTime',
    'LocalDateTime',
    'LastTriggerUSec',
    'NextElapseUSecRealtime',
    'ExecMainStartTimestamp',
    'Launch Time',
    'Ref time (UTC)',
    'SystemTime',
    'conditions / lastTransitionTime',
    'managedFields / time',
    'Health / Log / Start',
    'Health / Log / End',
    'Date/Time',
    'NEXT',
    'LAST',
    'last_updated',
    'last_modified',
    'date_registered',
    'tag_last_pushed',
    'tag_last_pulled',
    'images [1] / last_pushed',
    'images [1] / last_pulled',
  ]) {
    if (!machineMaintenanceIsTimestampField(field)) {
      throw StateError('遗漏日期字段：$field');
    }
  }
  for (final field in [
    'PID',
    '名称',
    'CommandLine',
    'CPUUsageNSec',
    'TIME',
    '累计 CPU 时间',
    '运行时长',
    'TimeoutStartUSec',
    'NextElapseUSecMonotonic',
    'ActiveEnterTimestampMonotonic',
    '过期时间',
    'star_count',
    'pull_count',
    'storage_size',
  ]) {
    if (machineMaintenanceIsTimestampField(field)) {
      throw StateError('误识别日期字段：$field');
    }
  }
  stdout.writeln('运维日期格式、服务器时间、Unix 精度、非法日期与字段隔离检查通过。');
}
