import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_maintenance_duration.dart';

void main() {
  void check(
    String raw,
    String? expected, {
    String field = '',
    String locale = 'zh',
  }) {
    final actual = machineMaintenanceReadableDuration(
      raw,
      field: field,
      languageCode: locale,
    );
    if (actual != expected) {
      throw StateError('时长转换失败：$raw → $actual，预期 $expected');
    }
  }

  check('24270.37 s', '6 小时 44 分 30.37 秒');
  check('631.00 s', '10 分 31 秒');
  check('60000 ms', '1 分');
  check('59.999 s', '1 分');
  check('1000 ns', '1 微秒');
  check('500 µs', '500 微秒');
  check('0 s', '0 秒');
  check('-90 s', '-1 分 30 秒');
  check('2h 30min', '2 小时 30 分');
  check('02:03.45', '2 分 3.45 秒', field: 'TIME');
  check('2-03:04:05', '2 天 3 小时 4 分', field: '运行时长');
  check('120000000000', '2 分', field: 'CPUUsageNSec');
  check('2000000', '2 秒', field: 'RestartUSec');
  check('61.5 s', '1 min 1,5 s', locale: 'fr');
  for (final raw in [
    '—',
    'N/A',
    'infinity',
    'NaN s',
    '1234',
    '2026-09-30 12:01:02',
    '12:30',
    'localhost:1234',
    '1s garbage',
    '1 GB',
  ]) {
    check(raw, null);
  }
  check('02:61', null, field: 'TIME');
  check('123456789', null, field: 'ActiveEnterTimestampMonotonic');
  stdout.writeln('时间单位、累计时长、精度边界、语言与误识别检查通过。');
}
