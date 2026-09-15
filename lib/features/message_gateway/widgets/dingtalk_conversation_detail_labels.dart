import 'package:flutter/widgets.dart';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';

const String kDingTalkDetailSettingsKey = '设置';
const String kDingTalkDetailNotificationKey = '通知';
const String kDingTalkDetailValueKey = '值';
const String kDingTalkDetailItemUnit = '项';
const String kDingTalkDetailPeopleUnit = '人';
const String kDingTalkDetailExtendedFieldPrefix = '扩展字段 · ';
const String kDingTalkDetailExtensionKey = '扩展属性';
const String kDingTalkDetailDepartmentProfileKey = '部门详情';
const String kDingTalkDetailNameKey = '姓名';
const String kDingTalkDetailTitleNameKey = '名称';
const String kDingTalkDetailRoleKey = '群内角色';
const String kDingTalkDetailRoleTypeKey = '角色类型';
const String kDingTalkDetailOwnerRole = '群主';
const String kDingTalkDetailAdminRole = '管理员';
const String kDingTalkDetailMemberRole = '普通成员';
const int kDingTalkDetailFlattenMaxDepth = 12;

const Set<String> kDingTalkDetailHoistLabelStems = <String>{
  kDingTalkDetailSettingsKey,
  kDingTalkDetailExtensionKey,
  kDingTalkDetailDepartmentProfileKey,
};

const Set<String> kDingTalkDetailHiddenLabelStems = <String>{'头像媒体标识', '是否单聊'};

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

bool dingTalkDetailIsHiddenLabel(String raw) {
  return kDingTalkDetailHiddenLabelStems.contains(
    dingTalkDetailLabelParts(raw).stem,
  );
}

String? dingTalkDetailRoleTypeZh(Object? value) {
  final code = switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text.trim()),
    _ => null,
  };
  return switch (code) {
    1 => kDingTalkDetailOwnerRole,
    2 => kDingTalkDetailAdminRole,
    3 => kDingTalkDetailMemberRole,
    _ => null,
  };
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

int dingTalkDetailVisibleCount(Object? value) {
  final flattened = dingTalkFlattenDetailValue(value);
  if (flattened is Map) {
    return flattened.keys
        .where((key) => !dingTalkDetailIsHiddenLabel(key))
        .length;
  }
  if (flattened is List) return flattened.length;
  return dingTalkDetailHasContent(flattened) ? 1 : 0;
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
      if (dingTalkDetailIsHiddenLabel(entry.key)) continue;
      final nested = dingTalkFlattenDetailValue(entry.value, depth + 1);
      if (!dingTalkDetailHasContent(nested)) continue;
      cleaned[entry.key] = nested;
    }
    final merged = <String, Object?>{};
    void put(String key, Object? nested) {
      if (dingTalkDetailIsHiddenLabel(key) ||
          !dingTalkDetailHasContent(nested)) {
        return;
      }
      if (!merged.containsKey(key)) merged[key] = nested;
    }

    String? promotedRole;
    for (final entry in cleaned.entries) {
      final stem = dingTalkDetailLabelParts(entry.key).stem;
      final nested = entry.value;
      if (stem == kDingTalkDetailRoleTypeKey) {
        promotedRole ??= dingTalkDetailRoleTypeZh(nested);
        continue;
      }
      if (kDingTalkDetailHoistLabelStems.contains(stem) && nested is Map) {
        for (final inner in stringKeyedMapFromValue(nested).entries) {
          put(inner.key, inner.value);
        }
      } else {
        put(entry.key, nested);
      }
    }
    final hasRole = merged.keys.any(
      (key) => dingTalkDetailLabelParts(key).stem == kDingTalkDetailRoleKey,
    );
    if (promotedRole != null && !hasRole) {
      merged[kDingTalkDetailRoleKey] = promotedRole;
    }
    return merged;
  }
  return value;
}

Map<String, Object?> dingTalkDetailAsMap(Object? value) {
  final flattened = dingTalkFlattenDetailValue(value);
  if (flattened is Map) return stringKeyedMapFromValue(flattened);
  return const <String, Object?>{};
}
