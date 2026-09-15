import 'package:flutter/widgets.dart';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';

const String kDingTalkDetailSettingsKey = '设置';
const String kDingTalkDetailNotificationKey = '通知';
const String kDingTalkDetailValueKey = '值';
const String kDingTalkDetailItemUnit = '项';
const String kDingTalkDetailPeopleUnit = '人';
const String kDingTalkDetailExtendedFieldPrefix = '扩展字段 · ';
const int kDingTalkDetailFlattenMaxDepth = 12;

final RegExp _dingtalkDetailDuplicateSuffixPattern = RegExp(r'^(.*) (\d+)$');
final RegExp _dingtalkDetailCjkPattern = RegExp(r'[\u4e00-\u9fff]');

const Set<String> kDingTalkDetailFlagLabels = <String>{
  kDingTalkDetailNotificationKey,
  '管理员权限',
  '主管权限',
  '企业负责人',
  '聊天类型',
  '是否单聊',
};

({String stem, String? suffix}) dingTalkDetailLabelParts(String raw) {
  final trimmed = raw.trim();
  final match = _dingtalkDetailDuplicateSuffixPattern.firstMatch(trimmed);
  if (match == null) return (stem: trimmed, suffix: null);
  return (stem: match.group(1)!, suffix: match.group(2));
}

bool dingTalkDetailLabelHasCjk(String value) =>
    _dingtalkDetailCjkPattern.hasMatch(value);

bool dingTalkDetailIsFlagLabel(String canonicalZh) {
  final stem = dingTalkDetailLabelParts(canonicalZh).stem;
  return stem.startsWith('是否') || kDingTalkDetailFlagLabels.contains(stem);
}

bool dingTalkDetailHasContent(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  if (value is List) return value.isNotEmpty;
  return true;
}

bool? dingTalkDetailBinaryFlag(Object? value) {
  if (value is bool) return value;
  if (value is num && (value == 0 || value == 1)) return value == 1;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes') return true;
    if (text == '0' || text == 'false' || text == 'no') return false;
  }
  return null;
}

String dingTalkDetailYesLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '是',
    zhHant: '是',
    en: 'Yes',
    fr: 'Oui',
    de: 'Ja',
    ja: 'はい',
  );
}

String dingTalkDetailNoLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '否',
    zhHant: '否',
    en: 'No',
    fr: 'Non',
    de: 'Nein',
    ja: 'いいえ',
  );
}

String dingTalkDetailOnLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '开启',
    zhHant: '開啟',
    en: 'On',
    fr: 'Activé',
    de: 'Ein',
    ja: 'オン',
  );
}

String dingTalkDetailOffLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '关闭',
    zhHant: '關閉',
    en: 'Off',
    fr: 'Désactivé',
    de: 'Aus',
    ja: 'オフ',
  );
}

String dingTalkDetailExtendedFieldLabel(BuildContext context, String suffix) {
  final prefix = openHandLocalizedText(
    context,
    zh: '扩展字段',
    zhHant: '擴展欄位',
    en: 'Extended field',
    fr: 'Champ étendu',
    de: 'Erweitertes Feld',
    ja: '拡張フィールド',
  );
  final trimmed = suffix.trim();
  return trimmed.isEmpty ? prefix : '$prefix · $trimmed';
}

Object? dingTalkFlattenDetailValue(Object? value, [int depth = 0]) {
  if (depth >= kDingTalkDetailFlattenMaxDepth) return value;
  if (value is List) {
    final items = <Object?>[
      for (final item in value)
        if (dingTalkDetailHasContent(item))
          dingTalkFlattenDetailValue(item, depth + 1),
    ];
    if (items.isEmpty) return null;
    if (items.length == 1) return items.first;
    return items;
  }
  if (value is Map) {
    final cleaned = <String, Object?>{};
    for (final entry in stringKeyedMapFromValue(value).entries) {
      final nested = dingTalkFlattenDetailValue(entry.value, depth + 1);
      if (!dingTalkDetailHasContent(nested)) continue;
      cleaned[entry.key] = nested;
    }
    if (cleaned.length == 1) {
      final only = cleaned.entries.first;
      if (dingTalkDetailLabelParts(only.key).stem ==
          kDingTalkDetailSettingsKey) {
        return dingTalkFlattenDetailValue(only.value, depth + 1);
      }
    }
    return cleaned;
  }
  return value;
}
