import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:openhand/features/machine_terminal/machine_egress.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  const primary = 'https://ipwho.is/';
  const secondary = 'https://ipapi.co/json/';
  for (final entry in {
    'zh': 'zh-CN',
    'en': 'en',
    'de': 'de',
    'fr': 'fr',
    'ja': 'ja',
    'invalid; command': 'en',
  }.entries) {
    final command = machineEgressCommand(
      primary,
      windows: false,
      language: entry.key,
    );
    check(
      command.contains('https://ipwho.is/?lang=${entry.value}'),
      '查询语言未正确映射',
    );
    check(!command.contains('invalid; command'), '查询语言未经过白名单过滤');
    check(
      !machineEgressCommand(
        secondary,
        windows: false,
        language: entry.key,
      ).contains('?lang='),
      '备用接口不应附加不支持的语言参数',
    );
    final bytes = base64Decode(
      machineEgressCommand(
        primary,
        windows: true,
        language: entry.key,
      ).split(' ').last,
    );
    final script = String.fromCharCodes([
      for (var i = 0; i < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8,
    ]);
    check(
      script.contains('https://ipwho.is/?lang=${entry.value}'),
      'Windows 查询语言未正确映射',
    );
  }
  final sample = jsonEncode({
    'success': true,
    'ip': '8.8.8.8',
    'type': 'IPv4',
    'country': 'United States',
    'city': 'Mountain View',
    'latitude': 0,
    'longitude': -122.08,
    'connection': {'asn': 15169, 'isp': 'Google', 'org': 'Google LLC'},
    'timezone': {'id': 'America/Los_Angeles', 'is_dst': false, 'offset': 0},
    'security': {'hosting': true},
    'custom': {
      'items': ['甲', '乙'],
    },
    'postal': null,
  });
  final report = MachineEgressReport.parse(sample, source: primary);
  check(report.ip == '8.8.8.8' && report.version == 'IPv4', '出口地址解析错误');
  check(report.source == 'ipwho.is', '数据源标识错误');
  final rows = report.groups.values.expand((rows) => rows).toList();
  check(rows.any((row) => row[0] == '纬度' && row[1] == '0'), '零坐标丢失');
  check(rows.any((row) => row[0] == '夏令时' && row[1] == 'false'), '布尔值丢失');
  check(
    rows.any((row) => row[0] == '互联网服务商' && row[1] == 'Google'),
    '嵌套网络归属未解析',
  );
  check(
    rows.any((row) => row[0] == 'custom.items[2]' && row[1] == '乙'),
    '扩展字段丢失',
  );
  check(rows.every((row) => row[0] != '机房'), '不能推断未提供的机房信息');
  final ipv6 = MachineEgressReport.parse(
    jsonEncode({
      'ip': '2001:4860:4860::8888',
      'country': 'US',
      'country_name': 'United States',
      'org': 'Google',
      'timezone': 'America/Los_Angeles',
      'in_eu': false,
    }),
    source: secondary,
  );
  check(ipv6.version == 'IPv6', 'IPv6 未识别');
  check(
    ipv6.groups['地理位置']!.any((row) => row[0] == '国家代码' && row[1] == 'US'),
    '备用接口国家代码映射错误',
  );
  for (final invalid in [
    '',
    '<html>服务不可用</html>',
    '[]',
    '{}',
    '{"success":false,"ip":"8.8.8.8"}',
    '{"error":true,"ip":"8.8.8.8"}',
    '{"ip":"127.0.0.1"}',
    '{"ip":"::"}',
    '{"ip":"not-an-ip"}',
    'x' * (machineEgressOutputLimit + 1),
  ]) {
    try {
      MachineEgressReport.parse(invalid, source: primary);
      throw StateError('错误响应被接受');
    } on MachineEgressException {
      // 无效响应必须交由备用接口或失败状态处理。
    }
  }
  var calls = 0;
  final fallback = await queryMachineEgress(
    run: (command) async {
      calls++;
      return calls == 1 ? '{"success":false}' : sample;
    },
    windows: false,
    isCancelled: () => false,
  );
  check(calls == 2 && fallback.source == 'ipapi.co', '接口失败后未切换备用源');
  calls = 0;
  for (final failure in ['tool', 'timeout', 'cancelled']) {
    calls = 0;
    try {
      await queryMachineEgress(
        run: (_) async {
          calls++;
          if (failure == 'timeout') throw TimeoutException('模拟超时');
          return '{"egress_error":"tool"}';
        },
        windows: false,
        isCancelled: () => failure == 'cancelled',
      );
      throw StateError('失败被错误忽略');
    } on MachineEgressException catch (error) {
      check(error.code == failure, '错误分类不正确');
      check(
        calls ==
            (failure == 'cancelled'
                ? 0
                : failure == 'tool'
                ? 1
                : 2),
        '查询次数未受限制',
      );
    }
  }
  calls = 0;
  try {
    await queryMachineEgress(
      run: (_) async {
        calls++;
        return sample;
      },
      windows: false,
      isCancelled: () => calls > 0,
    );
    throw StateError('取消后仍返回结果');
  } on MachineEgressException catch (error) {
    check(error.code == 'cancelled' && calls == 1, '取消后继续请求备用源');
  }
  final many = MachineEgressReport.parse(
    jsonEncode({'ip': '8.8.8.8', 'items': List.generate(1000, (i) => i)}),
    source: primary,
  );
  check(many.groups.values.expand((rows) => rows).length == 128, '扩展字段数量没有上限');

  if (!Platform.isWindows) {
    final directory = await Directory.systemTemp.createTemp('openhand-egress-');
    try {
      final curl = File('${directory.path}/curl');
      await Link('${directory.path}/head').create('/usr/bin/head');
      await curl.writeAsString('#!/bin/sh\nprintf \'%s\' \'$sample\'\n');
      await Process.run('/bin/chmod', ['+x', curl.path]);
      final result = await Process.run(
        '/bin/sh',
        ['-c', machineEgressCommand(primary, windows: false)],
        environment: {'PATH': directory.path},
      );
      check(
        result.exitCode == 0 &&
            MachineEgressReport.parse(
                  result.stdout as String,
                  source: primary,
                ).ip ==
                report.ip,
        'POSIX 命令执行失败',
      );
      await curl.delete();
      final wget = File('${directory.path}/wget');
      await wget.writeAsString('#!/bin/sh\nprintf \'%s\' \'$sample\'\n');
      await Process.run('/bin/chmod', ['+x', wget.path]);
      final viaWget = await Process.run(
        '/bin/sh',
        ['-c', machineEgressCommand(primary, windows: false)],
        environment: {'PATH': directory.path},
      );
      check(
        MachineEgressReport.parse(
              viaWget.stdout as String,
              source: primary,
            ).ip ==
            report.ip,
        'wget 后备工具无法获取出口',
      );
      await wget.writeAsString('#!/bin/sh\n/usr/bin/head -c 70000 /dev/zero\n');
      final bounded = await Process.run(
        '/bin/sh',
        ['-c', machineEgressCommand(primary, windows: false)],
        environment: {'PATH': directory.path},
      );
      check(
        (bounded.stdout as String).length == machineEgressOutputLimit + 1,
        '命令响应缺少读取上限',
      );
      await wget.delete();
      final missing = await Process.run(
        '/bin/sh',
        ['-c', machineEgressCommand(primary, windows: false)],
        environment: {'PATH': directory.path},
      );
      check((missing.stdout as String).contains('"tool"'), '缺失下载工具未报告');
    } finally {
      await directory.delete(recursive: true);
    }
  }
  final encoded = machineEgressCommand(primary, windows: true).split(' ').last;
  final bytes = base64Decode(encoded);
  final script = String.fromCharCodes([
    for (var i = 0; i < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8,
  ]);
  check(
    script.contains('https://ipwho.is/') &&
        script.contains('ReadBlock') &&
        script.contains('finally'),
    'Windows 命令未限制响应或释放资源',
  );
  if (Platform.environment['OPENHAND_EGRESS_LIVE'] == '1' &&
      !Platform.isWindows) {
    final live = await queryMachineEgress(
      run: (command) async {
        final result = await Process.run('/bin/sh', ['-c', command]);
        return result.stdout as String;
      },
      windows: false,
      isCancelled: () => false,
    );
    stdout.writeln(
      '本机真实接口查询通过：${live.source}，${live.version}，${live.groups.length} 个信息分组。',
    );
  }
  stdout.writeln('出口地址解析、备用源、查询上限、取消和跨平台命令检查通过。');
}
