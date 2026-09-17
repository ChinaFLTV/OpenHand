import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'localized_text.dart';

/// 按当前语言紧凑显示非负计数。
String openHandCompactCountLabel(BuildContext context, int value) {
  final safe = value < 0 ? 0 : value;
  try {
    return NumberFormat.compact(
      locale: Localizations.localeOf(context).toString(),
    ).format(safe);
  } on ArgumentError {
    return '$safe';
  }
}

/// 当前语言下的「每秒」单位，避免中文界面残留 `/s`。
String openHandPerSecondUnit(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '/秒',
    zhHant: '/秒',
    en: '/s',
    fr: '/s',
    de: '/s',
    ja: '/秒',
  );
}

String openHandRatePerSecond(
  BuildContext context,
  num value, {
  int fractionDigits = 0,
}) {
  return '${_formatRate(value, fractionDigits)}${openHandPerSecondUnit(context)}';
}

String openHandCharsPerSecondLabel(
  BuildContext context,
  num value, {
  int fractionDigits = 0,
}) {
  final rendered = _formatRate(value, fractionDigits);
  return openHandLocalizedText(
    context,
    zh: '$rendered 字/秒',
    zhHant: '$rendered 字/秒',
    en: '$rendered chars/s',
    fr: '$rendered car./s',
    de: '$rendered Zeichen/s',
    ja: '$rendered 文字/秒',
  );
}

String openHandCardsPerSecondLabel(
  BuildContext context,
  num value, {
  int fractionDigits = 0,
}) {
  final rendered = _formatRate(value, fractionDigits);
  return openHandLocalizedText(
    context,
    zh: '$rendered 卡/秒',
    zhHant: '$rendered 卡/秒',
    en: '$rendered cards/s',
    fr: '$rendered cartes/s',
    de: '$rendered Karten/s',
    ja: '$rendered カード/秒',
  );
}

String openHandTokensPerSecondLabel(
  BuildContext context,
  num value, {
  int fractionDigits = 1,
}) {
  final rendered = _formatRate(value, fractionDigits);
  return openHandLocalizedText(
    context,
    zh: '$rendered Token/秒',
    zhHant: '$rendered Token/秒',
    en: '$rendered tok/s',
    fr: '$rendered tok/s',
    de: '$rendered Tok/s',
    ja: '$rendered Token/秒',
  );
}

/// 相对秒数：中文用「秒前」，不再夹英文 `s`。
String openHandSecondsAgoLabel(BuildContext context, int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return openHandLocalizedText(
    context,
    zh: '$safe秒前',
    zhHant: '$safe秒前',
    en: '${safe}s ago',
    fr: 'il y a ${safe}s',
    de: 'vor ${safe}s',
    ja: '$safe秒前',
  );
}

String openHandMinutesAgoLabel(BuildContext context, int minutes) {
  final safe = minutes < 0 ? 0 : minutes;
  return openHandLocalizedText(
    context,
    zh: '$safe分钟前',
    zhHant: '$safe分鐘前',
    en: '${safe}m ago',
    fr: 'il y a $safe min',
    de: 'vor $safe Min.',
    ja: '$safe分前',
  );
}

String openHandHoursAgoLabel(BuildContext context, int hours) {
  final safe = hours < 0 ? 0 : hours;
  return openHandLocalizedText(
    context,
    zh: '$safe小时前',
    zhHant: '$safe小時前',
    en: '${safe}h ago',
    fr: 'il y a $safe h',
    de: 'vor $safe Std.',
    ja: '$safe時間前',
  );
}

String openHandSecondsRangeAgoLabel(
  BuildContext context, {
  required int startSeconds,
  required int endSeconds,
}) {
  final start = startSeconds < 0 ? 0 : startSeconds;
  final end = endSeconds < start ? start : endSeconds;
  if (start == end) {
    return openHandSecondsAgoLabel(context, start);
  }
  return openHandLocalizedText(
    context,
    zh: '$start–$end秒前',
    zhHant: '$start–$end秒前',
    en: '$start–${end}s ago',
    fr: 'il y a $start–$end s',
    de: 'vor $start–$end s',
    ja: '$start–$end秒前',
  );
}

String _formatRate(num value, int fractionDigits) {
  if (fractionDigits <= 0) {
    return '${value.round()}';
  }
  return value.toStringAsFixed(fractionDigits);
}
