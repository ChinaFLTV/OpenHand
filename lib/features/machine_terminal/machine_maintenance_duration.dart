const _durationUnits = <String, double>{
  'ns': 1e-9,
  'nsec': 1e-9,
  'us': 1e-6,
  'µs': 1e-6,
  'μs': 1e-6,
  'usec': 1e-6,
  'ms': .001,
  'msec': .001,
  's': 1,
  'sec': 1,
  'min': 60,
  'h': 3600,
  'hr': 3600,
  'd': 86400,
};

final _durationTokens = RegExp(
  r'(\d+(?:\.\d+)?)\s*(nsec|usec|msec|sec|min|hr|ns|us|µs|μs|ms|s|h|d)',
);

/// 只转换明确的时长；日期、时刻、标识符和不可用值保持原文。
String? machineMaintenanceReadableDuration(
  String raw, {
  String field = '',
  String languageCode = 'en',
  String? scriptCode,
}) {
  final text = raw.trim();
  final key = field.toLowerCase();
  if (const {
    '名称',
    'name',
    'pid',
    'id',
    'uuid',
    '路径',
    'path',
    '启动命令',
    'command',
  }.contains(key)) {
    return null;
  }
  double? seconds;

  final unsigned = text.replaceFirst(RegExp('^[+-]'), '');
  final matches = _durationTokens.allMatches(unsigned).toList();
  if (matches.isNotEmpty &&
      unsigned.replaceAll(_durationTokens, '').trim().isEmpty) {
    seconds = 0;
    for (final match in matches) {
      seconds = seconds! + double.parse(match[1]!) * _durationUnits[match[2]]!;
    }
    if (text.startsWith('-')) seconds = -seconds!;
  } else if (!key.contains('timestamp') && !key.contains('monotonic')) {
    final unit = key.endsWith('nsec')
        ? 1e-9
        : key.endsWith('usec')
        ? 1e-6
        : key.endsWith('msec')
        ? .001
        : null;
    if (unit != null) {
      final number = double.tryParse(text);
      if (number != null) seconds = number * unit;
    } else if (const {
      'time',
      'cputime',
      'elapsed',
      'etime',
      '累计 cpu 时间',
      '运行时长',
      '运行时间',
    }.contains(key)) {
      final clock = RegExp(
        r'^(?:(\d+)-)?(\d+):(\d{2}(?:\.\d+)?)(?::(\d{2}(?:\.\d+)?))?$',
      ).firstMatch(text);
      if (clock != null) {
        final first = double.parse(clock[2]!);
        final second = double.parse(clock[3]!);
        final third = double.tryParse(clock[4] ?? '');
        if (second < 60 &&
            (third == null || second == second.floorToDouble()) &&
            (third == null || third < 60) &&
            (clock[1] == null || (third != null && first < 24))) {
          seconds =
              (double.tryParse(clock[1] ?? '') ?? 0) * 86400 +
              (third == null
                  ? first * 60 + second
                  : first * 3600 + second * 60 + third);
        }
      }
    }
  }
  if (seconds == null || !seconds.isFinite || seconds.abs() >= 1e15) {
    return null;
  }
  final zh = languageCode == 'zh';
  final ja = languageCode == 'ja';
  final labels = zh
      ? (scriptCode == 'Hant'
            ? ['天', '小時', '分', '秒', '毫秒', '微秒', '奈秒']
            : ['天', '小时', '分', '秒', '毫秒', '微秒', '纳秒'])
      : ja
      ? ['日', '時間', '分', '秒', 'ms', 'µs', 'ns']
      : languageCode == 'de'
      ? ['T', 'Std.', 'Min.', 's', 'ms', 'µs', 'ns']
      : languageCode == 'fr'
      ? ['j', 'h', 'min', 's', 'ms', 'µs', 'ns']
      : ['d', 'h', 'min', 's', 'ms', 'µs', 'ns'];
  var remaining = seconds.abs();
  final parts = <String>[];
  String digits(double value) {
    var result = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    if (result.isEmpty) result = '0';
    return const ['de', 'fr'].contains(languageCode)
        ? result.replaceAll('.', ',')
        : result;
  }

  if (remaining < 1 && remaining > 0) {
    final index = remaining >= .001
        ? 4
        : remaining >= .000001
        ? 5
        : 6;
    final factor = index == 4
        ? 1000
        : index == 5
        ? 1000000
        : 1000000000;
    return '${seconds < 0 ? '-' : ''}${digits(remaining * factor)} ${labels[index]}';
  }
  // 先按百分之一秒舍入再拆分，避免出现“60 秒”或浮点尾数。
  remaining = (remaining * 100).roundToDouble() / 100;
  for (var i = 0; i < 4; i++) {
    final scale = const [86400.0, 3600.0, 60.0, 1.0][i];
    final value = i == 3 ? remaining : (remaining / scale).floorToDouble();
    if (value > 0 || (i == 3 && parts.isEmpty)) {
      parts.add('${digits(value)} ${labels[i]}');
    }
    remaining = ((remaining - value * scale) * 100).roundToDouble() / 100;
    if (parts.length == 3) break;
  }
  return '${seconds < 0 ? '-' : ''}${parts.join(' ')}';
}
