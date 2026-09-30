import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../shared/util/platform_shell.dart';

const machineEgressCacheDuration = Duration(minutes: 5);
const machineEgressTimeout = Duration(seconds: 12);
const machineEgressOutputLimit = 65536;
const _egressProviders = ['https://ipwho.is/', 'https://ipapi.co/json/'];

/// 请求在目标终端执行，不使用桌面端网络推断远程机器的出口。
String machineEgressCommand(
  String endpoint, {
  required bool windows,
  String language = 'en',
}) {
  if (!_egressProviders.contains(endpoint)) {
    throw ArgumentError('不支持的出口地址数据源。');
  }
  final locale = switch (language) {
    'zh' => 'zh-CN',
    'de' || 'fr' || 'ja' => language,
    _ => 'en',
  };
  final url = endpoint == _egressProviders.first
      ? '$endpoint?lang=$locale'
      : endpoint;
  if (windows) {
    return powerShellEncodedCommand('''
\$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new(\$false)
\$response = \$null; \$reader = \$null
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  \$request = [Net.HttpWebRequest]::Create('$url')
  \$request.Timeout = 8000; \$request.ReadWriteTimeout = 8000
  \$request.AllowAutoRedirect = \$false
  \$request.Accept = 'application/json'
  \$request.UserAgent = 'OpenHand'
  \$response = \$request.GetResponse()
  \$reader = [IO.StreamReader]::new(\$response.GetResponseStream())
  \$buffer = New-Object char[] ${machineEgressOutputLimit + 1}
  \$count = \$reader.ReadBlock(\$buffer, 0, \$buffer.Length)
  if (\$count -gt $machineEgressOutputLimit) { throw '响应超过读取上限' }
  [Console]::Write((-join \$buffer[0..(\$count - 1)]))
} catch { [Console]::Write('{"egress_error":"request"}') }
finally {
  if (\$null -ne \$reader) { \$reader.Dispose() }
  if (\$null -ne \$response) { \$response.Dispose() }
}
''');
  }
  return '''
if command -v curl >/dev/null 2>&1; then
  (curl --silent --fail --connect-timeout 4 --max-time 8 --max-filesize $machineEgressOutputLimit --proto '=https' --user-agent OpenHand --header 'Accept: application/json' ${posixShellQuote(url)} 2>/dev/null || printf '{"egress_error":"request"}') | head -c ${machineEgressOutputLimit + 1}
elif command -v wget >/dev/null 2>&1; then
  wget -q -T 8 -t 1 -O - ${posixShellQuote(url)} 2>/dev/null | head -c ${machineEgressOutputLimit + 1}
else
  printf '{"egress_error":"tool"}'
fi
''';
}

class MachineEgressException implements Exception {
  const MachineEgressException(this.code);
  final String code;
  @override
  String toString() => '出口地址查询失败：$code';
}

Future<MachineEgressReport> queryMachineEgress({
  required Future<String> Function(String command) run,
  required bool windows,
  String language = 'en',
  required bool Function() isCancelled,
}) async {
  var failure = const MachineEgressException('request');
  for (final endpoint in _egressProviders) {
    if (isCancelled()) throw const MachineEgressException('cancelled');
    try {
      final output = await run(
        machineEgressCommand(endpoint, windows: windows, language: language),
      );
      if (isCancelled()) throw const MachineEgressException('cancelled');
      return MachineEgressReport.parse(output, source: endpoint);
    } on MachineEgressException catch (error) {
      if (error.code == 'tool' || error.code == 'cancelled') rethrow;
      failure = error;
    } on TimeoutException {
      failure = const MachineEgressException('timeout');
    } on FormatException {
      failure = const MachineEgressException('invalid');
    }
  }
  throw failure;
}

class MachineEgressReport {
  factory MachineEgressReport.parse(String output, {required String source}) {
    if (output.length > machineEgressOutputLimit) {
      throw const MachineEgressException('invalid');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(output.trim());
    } on FormatException {
      throw const MachineEgressException('invalid');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const MachineEgressException('invalid');
    }
    if (decoded['egress_error'] != null) {
      throw MachineEgressException(
        decoded['egress_error'] == 'tool' ? 'tool' : 'request',
      );
    }
    if (decoded['success'] == false || decoded['error'] == true) {
      throw const MachineEgressException('request');
    }
    final address = InternetAddress.tryParse('${decoded['ip'] ?? ''}');
    if (address == null ||
        address.isLoopback ||
        address.isLinkLocal ||
        address.isMulticast ||
        address.rawAddress.every((byte) => byte == 0)) {
      throw const MachineEgressException('invalid');
    }
    final groups = <String, List<List<String>>>{};
    final hasCountryName = decoded.containsKey('country_name');
    var count = 0;
    void visit(Object? value, String key, int depth) {
      if (value == null || value == '' || count >= 128 || depth > 6) return;
      if (value is Map) {
        for (final entry in value.entries) {
          visit(
            entry.value,
            key.isEmpty ? '${entry.key}' : '$key.${entry.key}',
            depth + 1,
          );
        }
        return;
      }
      if (value is List) {
        for (var i = 0; i < value.length && count < 128; i++) {
          visit(value[i], '$key[${i + 1}]', depth + 1);
        }
        return;
      }
      if (const {'ip', 'type', 'version', 'success', 'error'}.contains(key)) {
        return;
      }
      final field = key == 'country' && hasCountryName
          ? ('地理位置', '国家代码')
          : _egressFields[key];
      final text = '$value';
      if (text.length > 2048) throw const MachineEgressException('invalid');
      groups.putIfAbsent(field?.$1 ?? '补充信息', () => []).add([
        field?.$2 ?? key,
        text,
      ]);
      count++;
    }

    visit(decoded, '', 0);
    return MachineEgressReport(
      ip: address.address,
      version: address.type == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6',
      source: Uri.parse(source).host,
      collectedAt: DateTime.now(),
      groups: Map.unmodifiable({
        for (final group in ['地理位置', '网络归属', '时区信息', '国家信息', '补充信息'])
          if (groups.containsKey(group))
            group: List<List<String>>.unmodifiable(
              groups[group]!.map(List<String>.unmodifiable),
            ),
      }),
    );
  }
  const MachineEgressReport({
    required this.ip,
    required this.version,
    required this.source,
    required this.collectedAt,
    required this.groups,
  });
  final String ip, version, source;
  final DateTime collectedAt;
  final Map<String, List<List<String>>> groups;
}

const _egressFields = <String, (String, String)>{
  'readme': ('补充信息', '描述'),
  'continent': ('地理位置', '洲'),
  'continent_code': ('地理位置', '洲代码'),
  'country': ('地理位置', '国家或地区'),
  'country_name': ('地理位置', '国家或地区'),
  'country_code': ('地理位置', '国家代码'),
  'country_code_iso3': ('地理位置', '三字母国家代码'),
  'region': ('地理位置', '地域'),
  'region_code': ('地理位置', '地域代码'),
  'city': ('地理位置', '城市'),
  'latitude': ('地理位置', '纬度'),
  'longitude': ('地理位置', '经度'),
  'postal': ('地理位置', '邮政编码'),
  'connection.asn': ('网络归属', '自治系统编号'),
  'asn': ('网络归属', '自治系统编号'),
  'connection.org': ('网络归属', '组织'),
  'org': ('网络归属', '组织'),
  'connection.isp': ('网络归属', '互联网服务商'),
  'isp': ('网络归属', '互联网服务商'),
  'connection.domain': ('网络归属', '归属域名'),
  'network': ('网络归属', '网络前缀'),
  'datacenter': ('网络归属', '机房'),
  'security.hosting': ('网络归属', '托管网络'),
  'security.proxy': ('网络归属', '代理网络'),
  'security.vpn': ('网络归属', 'VPN 网络'),
  'security.tor': ('网络归属', 'Tor 网络'),
  'timezone': ('时区信息', '时区'),
  'timezone.id': ('时区信息', '时区'),
  'timezone.abbr': ('时区信息', '时区简称'),
  'timezone.is_dst': ('时区信息', '夏令时'),
  'timezone.offset': ('时区信息', 'UTC 偏移（秒）'),
  'timezone.utc': ('时区信息', 'UTC 偏移'),
  'utc_offset': ('时区信息', 'UTC 偏移'),
  'timezone.current_time': ('时区信息', '查询时当地时间'),
  'is_eu': ('国家信息', '欧盟成员'),
  'in_eu': ('国家信息', '欧盟成员'),
  'calling_code': ('国家信息', '国际电话区号'),
  'country_calling_code': ('国家信息', '国际电话区号'),
  'capital': ('国家信息', '首都'),
  'country_capital': ('国家信息', '首都'),
  'borders': ('国家信息', '邻国代码'),
  'flag.img': ('国家信息', '旗帜图片地址'),
  'flag.emoji': ('国家信息', '旗帜'),
  'flag.emoji_unicode': ('国家信息', '旗帜字符编码'),
  'country_tld': ('国家信息', '国家顶级域名'),
  'currency': ('国家信息', '货币代码'),
  'currency.code': ('国家信息', '货币代码'),
  'currency.name': ('国家信息', '货币名称'),
  'currency.symbol': ('国家信息', '货币符号'),
  'currency_name': ('国家信息', '货币名称'),
  'languages': ('国家信息', '语言'),
  'country_area': ('国家信息', '国土面积（平方千米）'),
  'country_population': ('国家信息', '人口'),
};
