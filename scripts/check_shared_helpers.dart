import 'dart:io';

import 'package:openhand/shared/net/loopback_hosts.dart';
import 'package:openhand/shared/util/bounded_json_conversion.dart';
import 'package:openhand/shared/util/exponential_backoff.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';
import 'package:openhand/shared/util/message_frame_scan.dart';

/// 直接驱动抽出的共享实现：代表输入进、真实返回值出。
void main() {
  var failures = 0;
  failures += _checkJsonDecode();
  failures += _checkContentLength();
  failures += _checkBackoff();
  failures += _checkLoopback();
  failures += _checkStringFromValue();
  if (failures > 0) {
    stderr.writeln('[共享辅助检查] 失败 $failures 项。');
    exit(1);
  }
  stdout.writeln('[共享辅助检查] 通过。');
}

int _checkJsonDecode() {
  final decoded = decodeJsonTextUsingConfig(
    '{"a":1,"b":[true,null]}',
    maxTextCodeUnits: 64,
    config: kOpenHandProtocolJsonConversionConfig,
  );
  if (decoded is! Map || decoded['a'] != 1) {
    stderr.writeln('decodeJsonTextUsingConfig 未解析出对象字段 a=1');
    return 1;
  }
  try {
    decodeJsonTextUsingConfig('{"a":1}', maxTextCodeUnits: 3);
    stderr.writeln('decodeJsonTextUsingConfig 应对超长文本抛出 FormatException');
    return 1;
  } on FormatException {
    return 0;
  }
}

int _checkContentLength() {
  final parsed = parseHttpContentLengthHeader(
    'Content-Type: application/json\r\nContent-Length: 42\r\n',
    maxDigits: 8,
  );
  if (!parsed.found || parsed.value != 42) {
    stderr.writeln('parseHttpContentLengthHeader 未解析出 42，得到 $parsed');
    return 1;
  }
  final missing = parseHttpContentLengthHeader('Accept: */*\n', maxDigits: 8);
  if (missing.found || missing.value != null) {
    stderr.writeln('缺少 Content-Length 时应 found=false，得到 $missing');
    return 1;
  }
  final duplicate = parseHttpContentLengthHeader(
    'Content-Length: 1\nContent-Length: 2\n',
    maxDigits: 8,
  );
  if (!duplicate.found || duplicate.value != null) {
    stderr.writeln('重复 Content-Length 应判定无效，得到 $duplicate');
    return 1;
  }
  final invalid = parseHttpContentLengthHeader(
    'Content-Length: 12a\n',
    maxDigits: 8,
  );
  if (!invalid.found || invalid.value != null) {
    stderr.writeln('非数字 Content-Length 应判定无效，得到 $invalid');
    return 1;
  }
  return 0;
}

int _checkBackoff() {
  if (exponentialBackoffMs(attempt: 0, baseMs: 250, capMs: 4000) != 0) {
    stderr.writeln('attempt=0 的退避应为 0');
    return 1;
  }
  if (exponentialBackoffMs(attempt: 1, baseMs: 250, capMs: 4000) != 250) {
    stderr.writeln('第 1 次退避应为 250ms');
    return 1;
  }
  if (exponentialBackoffMs(attempt: 2, baseMs: 250, capMs: 4000) != 500) {
    stderr.writeln('第 2 次退避应为 500ms');
    return 1;
  }
  if (exponentialBackoffMs(attempt: 5, baseMs: 250, capMs: 4000) != 4000) {
    stderr.writeln('第 5 次退避应封顶 4000ms');
    return 1;
  }
  if (exponentialBackoffSeconds(attempt: 3, baseSeconds: 2, capSeconds: 10) !=
      8) {
    stderr.writeln('秒级退避 attempt=3 应为 8');
    return 1;
  }
  return 0;
}

int _checkLoopback() {
  if (!isLoopbackHost('127.0.0.1') ||
      !isLoopbackHost('localhost') ||
      !isLoopbackHost('LOCALHOST.localdomain') ||
      !isLoopbackHost('[::1]') ||
      !isLoopbackHost('::ffff:127.0.0.1')) {
    stderr.writeln('isLoopbackHost 未识别回环地址');
    return 1;
  }
  if (isLoopbackHost('example.com') || isLoopbackHost('8.8.8.8')) {
    stderr.writeln('isLoopbackHost 误判了非回环地址');
    return 1;
  }
  if (!kLoopbackHosts.contains('127.0.0.1')) {
    stderr.writeln('kLoopbackHosts 缺少 127.0.0.1');
    return 1;
  }
  return 0;
}

int _checkStringFromValue() {
  if (stringFromValue(null, fallback: 'x') != 'x') {
    stderr.writeln('stringFromValue(null) 未回落');
    return 1;
  }
  if (stringFromValue('  hi ') != 'hi') {
    stderr.writeln('stringFromValue 未 trim');
    return 1;
  }
  final map = stringKeyedMapFromValue(<Object?, Object?>{1: 'a'});
  if (map['1'] != 'a') {
    stderr.writeln('stringKeyedMapFromValue 未把键转为字符串');
    return 1;
  }
  return 0;
}
