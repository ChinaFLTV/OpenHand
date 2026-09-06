import 'dart:io';

import 'package:openhand/shared/net/http_status_utils.dart';
import 'package:openhand/shared/net/loopback_hosts.dart';
import 'package:openhand/shared/util/bounded_file_io.dart';
import 'package:openhand/shared/util/bounded_json_conversion.dart';
import 'package:openhand/shared/util/date_time_format.dart';
import 'package:openhand/shared/util/exponential_backoff.dart';
import 'package:openhand/shared/util/hex_encoding.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';
import 'package:openhand/shared/util/message_frame_scan.dart';
import 'package:openhand/shared/util/xml_escape.dart';

/// 直接驱动抽出的共享实现：代表输入进、真实返回值出。
Future<void> main() async {
  var failures = 0;
  failures += _checkJsonDecode();
  failures += _checkContentLength();
  failures += _checkBackoff();
  failures += _checkLoopback();
  failures += _checkStringFromValue();
  failures += _checkGrowableStringKeyedMap();
  failures += _checkHttpRetryableStatus();
  failures += _checkRgbHex();
  failures += _checkXmlEscape();
  failures += _checkCompactDuration();
  failures += await _checkTemporaryDirectoryLifecycle();
  if (failures > 0) {
    stderr.writeln('[共享辅助检查] 失败 $failures 项。');
    exit(1);
  }
  stdout.writeln('[共享辅助检查] 通过。');
}

Future<int> _checkTemporaryDirectoryLifecycle() async {
  Directory? directory;
  try {
    directory = await createTemporaryDirectoryBounded(
      prefix: 'openhand-shared-check-',
      timeout: const Duration(seconds: 2),
    );
    final invalidRoot = '${directory.parent.path}${Platform.pathSeparator}拒绝';
    final refused = await deleteTemporaryDirectoryBounded(
      directory,
      allowedRoot: invalidRoot,
    );
    if (refused || !await directory.exists()) {
      stderr.writeln('deleteTemporaryDirectoryBounded 未拒绝越界清理');
      return 1;
    }
    final deleted = await deleteTemporaryDirectoryBounded(directory);
    if (!deleted || await directory.exists()) {
      stderr.writeln('deleteTemporaryDirectoryBounded 未清理受管临时目录');
      return 1;
    }
    directory = null;
    return 0;
  } catch (error) {
    stderr.writeln('临时目录生命周期检查失败：$error');
    return 1;
  } finally {
    await deleteTemporaryDirectoryBounded(directory);
  }
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
  final durationBackoff = exponentialBackoffDuration(
    attempt: 5,
    base: const Duration(milliseconds: 250),
    cap: const Duration(seconds: 4),
  );
  if (durationBackoff.inMilliseconds !=
      exponentialBackoffMs(attempt: 5, baseMs: 250, capMs: 4000)) {
    stderr.writeln('Duration 退避应与毫秒公式一致，得到 $durationBackoff');
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
  if (!isLoopbackHostname('LOCALHOST.localdomain') ||
      !isLoopbackHostname('api.localhost') ||
      isLoopbackHostname('127.0.0.1') ||
      isLoopbackHostname('example.com')) {
    stderr.writeln('isLoopbackHostname 主机名判定错误');
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

int _checkGrowableStringKeyedMap() {
  final global = growableStringKeyedMapFromValue(null);
  global['body'] = <String, Object?>{'n': 1};
  global['headers'] = <String, String>{'x': 'y'};
  final body = optionalStringKeyedMapFromValue(global['body']);
  if (body == null || body['n'] != 1) {
    stderr.writeln('growableStringKeyedMapFromValue(null) 写入 body 失败');
    return 1;
  }
  final headers = global['headers'];
  if (headers is! Map || headers['x'] != 'y') {
    stderr.writeln('growableStringKeyedMapFromValue(null) 写入 headers 失败');
    return 1;
  }

  const writtenTemperature = 0.4;
  final source = <String, Object?>{'topK': 8};
  final generationConfig = growableStringKeyedMapFromValue(source);
  generationConfig['temperature'] = writtenTemperature;
  if (identical(generationConfig, source) ||
      source.containsKey('temperature')) {
    stderr.writeln('growableStringKeyedMapFromValue 别名或回写了源映射');
    return 1;
  }
  if (generationConfig['topK'] != source['topK'] ||
      generationConfig['temperature'] != writtenTemperature) {
    stderr.writeln('growableStringKeyedMapFromValue 未保留源字段或写入失败');
    return 1;
  }
  return 0;
}

int _checkHttpRetryableStatus() {
  if (!isHttpTransientRetryableStatus(kHttpRequestTimeoutStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpTooEarlyStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpTooManyRequestsStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpInternalServerErrorStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpBadGatewayStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpServiceUnavailableStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpGatewayTimeoutStatusCode)) {
    stderr.writeln('isHttpTransientRetryableStatus 未识别瞬时失败状态码');
    return 1;
  }
  if (isHttpTransientRetryableStatus(kHttpConflictStatusCode) ||
      isHttpTransientRetryableStatus(404) ||
      isHttpTransientRetryableStatus(kHttpSuccessStatusMin)) {
    stderr.writeln('isHttpTransientRetryableStatus 误判了非瞬时状态码');
    return 1;
  }
  if (!isHttpServerErrorStatus(501) || isHttpServerErrorStatus(499)) {
    stderr.writeln('isHttpServerErrorStatus 判定错误');
    return 1;
  }
  return 0;
}

int _checkRgbHex() {
  if (rgbHexFromArgb32(0xFF1E1E24) != '1e1e24') {
    stderr.writeln('rgbHexFromArgb32(0xFF1E1E24) 应为 1e1e24');
    return 1;
  }
  if (rgbHexFromArgb32(0x000000FF) != '0000ff') {
    stderr.writeln('rgbHexFromArgb32 未补齐 6 位');
    return 1;
  }
  return 0;
}

int _checkXmlEscape() {
  final escaped = escapeXmlAttribute('''a&b<"c">'d''');
  if (!escaped.contains('&amp;') ||
      !escaped.contains('&lt;') ||
      !escaped.contains('&quot;') ||
      !escaped.contains('&gt;') ||
      !escaped.contains('&apos;')) {
    stderr.writeln('escapeXmlAttribute 未转义全部 XML 属性字符，得到 $escaped');
    return 1;
  }
  if (escapeXmlAttribute('plain') != 'plain') {
    stderr.writeln('escapeXmlAttribute 不应改写无特殊字符的文本');
    return 1;
  }
  return 0;
}

int _checkCompactDuration() {
  if (formatCompactDuration(const Duration(seconds: 5)) != '5s') {
    stderr.writeln('formatCompactDuration(5s) 应为 5s');
    return 1;
  }
  if (formatCompactDuration(const Duration(seconds: 65)) != '1m 5s') {
    stderr.writeln('formatCompactDuration(65s) 应为 1m 5s');
    return 1;
  }
  if (formatCompactDurationMs(250) !=
      formatCompactDuration(const Duration(milliseconds: 250))) {
    stderr.writeln('formatCompactDurationMs 应与 Duration 形式一致');
    return 1;
  }
  return 0;
}
