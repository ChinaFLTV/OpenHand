import '../../shared/util/date_time_format.dart';

const _timestampFields = {
  '时间',
  '创建时间',
  '启动时间',
  '最近启动时间',
  '开始时间',
  '结束时间',
  '完成时间',
  '更新时间',
  '修改时间',
  '登录时间',
  '本地时间',
  '采样时间',
  '最近轮转',
  'created',
  'createdat',
  'started',
  'startedat',
  'finishedat',
  'updatedat',
  'last_updated',
  'last_modified',
  'date_registered',
  'tag_last_pushed',
  'tag_last_pulled',
  'last_pushed',
  'last_pulled',
  'creationdate',
  'installdate',
  'lasttransitiontime',
  'lastprobetime',
  'lastheartbeattime',
  'start',
  'end',
  'time',
  'starttime',
  'systemtime',
  'date/time',
  'next',
  'last',
  'endtime',
  'lastbootuptime',
  'localdatetime',
  'lasttriggerusec',
  'nextelapseusecrealtime',
  'lastruntime',
  'nextruntime',
  'lastrun',
  'nextrun',
  'collectedat',
  'builddate',
  'mtime',
  'birthtime',
  'launchtime',
  'date',
  'utc',
  'reftime(utc)',
  'timecreated',
};
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
final _calendarTimestamp = RegExp(
  r'^(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+)?'
  r'(\d{4})-(\d{1,2})-(\d{1,2})'
  r'(?:[Tt -](\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:[.,]\d{1,9})?)?)?'
  r'(?:\s*(?:[Zz]|([+-])(\d{2}):?(\d{2}))?)'
  r'(?:\s+([A-Z]{2,5}))?$',
);
final _englishTimestamp = RegExp(
  r'^(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+)?'
  r'([A-Z][a-z]{2})\s+(\d{1,2})\s+'
  r'(\d{2}):(\d{2})(?::(\d{2}))?'
  r'(?:\s+[A-Z]{2,5})?(?:\s+(\d{4}))?$',
);
final _cimTimestamp = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\.\d{6}[+-]\d{3}$',
);
final _epochTimestamp = RegExp(r'^\d{10}(?:\d{3}){0,3}$');

/// 只识别绝对时间字段，避免把 CPU 时长、单调时钟和普通计数当成日期。
bool machineMaintenanceIsTimestampField(String field) {
  final leaf = field.split(' / ').last.trim();
  if (leaf == 'TIME') return false;
  final key = leaf.replaceAll(' ', '').toLowerCase();
  return _timestampFields.contains(key) || key.endsWith('timestamp');
}

/// 文本日期保留服务器的年月日与时分秒；Unix 时间戳按应用本地时间显示。
/// 无效值返回 null，由展示层保留原文；只在明确日期字段中启用纯数字解析。
String? machineMaintenanceTimestamp(String value, {bool allowEpoch = false}) {
  final text = value.trim();
  if (allowEpoch && _epochTimestamp.hasMatch(text)) {
    // 丢弃秒以下部分后再解析，避免纳秒大整数在 Web 上丢失精度。
    final seconds = int.parse(text.substring(0, 10));
    return formatListDateTime(
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    );
  }
  var match = _calendarTimestamp.firstMatch(text);
  late int year, month, day, hour, minute, second;
  if (match != null) {
    if (match[7] != null &&
        (int.parse(match[8]!) > 23 || int.parse(match[9]!) > 59)) {
      return null;
    }
    year = int.parse(match[1]!);
    month = int.parse(match[2]!);
    day = int.parse(match[3]!);
    hour = int.parse(match[4] ?? '0');
    minute = int.parse(match[5] ?? '0');
    second = int.parse(match[6] ?? '0');
  } else if ((match = _cimTimestamp.firstMatch(text)) != null) {
    year = int.parse(match![1]!);
    month = int.parse(match[2]!);
    day = int.parse(match[3]!);
    hour = int.parse(match[4]!);
    minute = int.parse(match[5]!);
    second = int.parse(match[6]!);
  } else if ((match = _englishTimestamp.firstMatch(text)) != null) {
    year = int.parse(match![6] ?? '${DateTime.now().year}');
    month = _months.indexOf(match[1]!) + 1;
    day = int.parse(match[2]!);
    hour = int.parse(match[3]!);
    minute = int.parse(match[4]!);
    second = int.parse(match[5] ?? '0');
  } else {
    return null;
  }
  final date = DateTime.utc(year, month, day, hour, minute, second);
  if (year < 1 ||
      date.year != year ||
      date.month != month ||
      date.day != day ||
      date.hour != hour ||
      date.minute != minute ||
      date.second != second) {
    return null;
  }
  return formatYearMonthDayHms(date);
}
