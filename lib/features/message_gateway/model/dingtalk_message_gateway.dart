import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../shared/model/dingtalk_multimodal_capability.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_normalization.dart';

String _normalizedDingTalkString(Object? value) {
  if (value == null) return '';
  final text = value.toString().trim();
  return text.toLowerCase() == 'null' ? '' : text;
}

final RegExp _dingtalkInvisibleTextPattern = RegExp(
  r'[\u200B-\u200D\u2060\uFEFF]',
);
final RegExp _dingtalkWhitespacePattern = RegExp(
  r'[\s\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+',
);
final RegExp _dingtalkDuplicatedLinkProjectionPattern = RegExp(
  r'(https?://\S+)\s+(?:url|uri)\s*[:：]\s*(https?://\S+)$',
  caseSensitive: false,
);
final RegExp _dingtalkLinkCardProjectionPrefixPattern = RegExp(
  r'^(?:[\[【](?:分享|链接|网页)[\]】]|分享链接(?:消息)?[:：]?)\s*',
  caseSensitive: false,
);
final RegExp _dingtalkSelfLabeledMarkdownLinkPattern = RegExp(
  r'^\[(https?://[^\]\r\n]+)\]\((https?://.+)\)$',
  caseSensitive: false,
);
const int _dingtalkEnhancedLinkMaxProjectionLines = 3;
const String _dingtalkEnhancedLinkSource = 'dd_link_enhance';
const String _dingtalkDesktopLinkSource = 'dingcardslide';
final RegExp _dingtalkMediaPlaceholderPattern = RegExp(
  r'\[(?:图片|图片消息|照片|图像|视频|视频消息|语音|语音消息|音频|音频消息|文件|文件消息|附件|媒体消息|image|image message|photo|picture|video|video message|voice|voice message|audio|audio message|file|file message|attachment|media|media message)\]'
  r'(?:\(\s*(?:mediaId|fileId)\s*=\s*[^)\s]+\s*\))?',
  caseSensitive: false,
);
final RegExp _dwsMediaDownloadHintPattern = RegExp(
  r'(?:^|\s)注意\s*[:：]\s*如需下载使用dws\s+chat\s+message\s+'
  r'download-media\s*命令下载\s*$',
  caseSensitive: false,
);

String _removeDingTalkDuplicatedLinkProjection(Object? value) {
  final text = _normalizedDingTalkString(value);
  final enhancedLink = _dingtalkEnhancedLinkProjectionUrl(text);
  if (enhancedLink != null) return enhancedLink;
  final match = _dingtalkDuplicatedLinkProjectionPattern.firstMatch(text);
  if (match == null) return text;
  final content = match.group(1)!;
  if (content != match.group(2)) return text;

  final prefix = text.substring(0, match.start).trim();
  if (prefix.isNotEmpty &&
      !_dingtalkLinkCardProjectionPrefixPattern.hasMatch(prefix)) {
    return text;
  }
  return content;
}

String? _dingtalkEnhancedLinkProjectionUrl(String text) {
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty || lines.length > _dingtalkEnhancedLinkMaxProjectionLines) {
    return null;
  }

  RegExpMatch? originalLink;
  var originalIndex = -1;
  for (var index = 0; index < lines.length; index++) {
    final match = _dingtalkSelfLabeledMarkdownLinkPattern.firstMatch(
      lines[index],
    );
    if (match == null || match.group(1) != match.group(2)) continue;
    final uri = Uri.tryParse(match.group(2)!);
    final enhanced =
        uri != null &&
        _uriHasQueryParameterValue(
          uri,
          key: 'from',
          value: _dingtalkEnhancedLinkSource,
        );
    if (enhanced != true || originalLink != null) continue;
    originalLink = match;
    originalIndex = index;
  }
  if (originalLink == null || originalIndex > 1) return null;
  if (originalIndex == 1 &&
      _dingtalkSelfLabeledMarkdownLinkPattern.hasMatch(lines.first)) {
    return null;
  }
  if (originalIndex + 1 < lines.length) {
    final desktopLink = _dingtalkSelfLabeledMarkdownLinkPattern.firstMatch(
      lines[originalIndex + 1],
    );
    if (desktopLink == null ||
        desktopLink.group(1) != desktopLink.group(2) ||
        !_isDingTalkDesktopLinkProjection(desktopLink.group(2)!)) {
      return null;
    }
    if (originalIndex + 2 != lines.length) return null;
  }
  return originalLink.group(2);
}

bool _uriHasQueryParameterValue(
  Uri uri, {
  required String key,
  required String value,
}) {
  final normalizedKey = key.toLowerCase();
  final normalizedValue = value.toLowerCase();
  return uri.queryParametersAll.entries.any(
    (entry) =>
        entry.key.toLowerCase() == normalizedKey &&
        entry.value.any(
          (candidate) => candidate.toLowerCase() == normalizedValue,
        ),
  );
}

bool _isDingTalkDesktopLinkProjection(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.toLowerCase() != 'applink.dingtalk.com') {
    return false;
  }
  final nestedUrls = uri.queryParametersAll.entries
      .where((entry) => entry.key.toLowerCase() == 'url')
      .expand((entry) => entry.value);
  for (final nestedUrl in nestedUrls) {
    final nestedUri = Uri.tryParse(nestedUrl);
    if (nestedUri != null &&
        _uriHasQueryParameterValue(
          nestedUri,
          key: 'from',
          value: _dingtalkDesktopLinkSource,
        )) {
      return true;
    }
  }
  return false;
}

/// 生成钉钉消息正文的比较值，消除平台回流时产生的换行和不可见字符差异。
String normalizeDingTalkMessageContentForComparison(Object? value) =>
    _removeDingTalkDuplicatedLinkProjection(value)
        .replaceAll(_dingtalkInvisibleTextPattern, '')
        .replaceAll(_dingtalkWhitespacePattern, ' ')
        .trim();

const Map<String, String> _dingtalkReactionEmojiMap = <String, String>{
  '拜托': '🙏',
  '抱拳': '🙏',
  '狗子': '🐶',
  '害羞': '😊',
  '暗中观察': '👀',
  '流鼻血': '🤧',
  '鞠躬': '🙇',
  '666': '🤙',
  '6664': '💯',
  'ok': '👌',
  'okay': '👌',
  '摊手': '🤷',
  '锦鲤': '🐟',
  '烟花': '🎆',
  '爆竹': '🧨',
  '灯笼': '🏮',
  '福': '🧧',
  '抠鼻': '👃',
  '感谢': '🙏',
  '赞': '👍',
  '点赞': '👍',
  'like': '👍',
  'thumbup': '👍',
  '拒绝': '👎',
  '憨笑': '😄',
  '爱意': '🥰',
  '残花': '🥀',
  '送花花': '💐',
  '傻笑': '😆',
  '微笑': '🙂',
  '可爱': '🥰',
  '色': '😍',
  '发呆': '😑',
  '老板': '🧑‍💼',
  'heart': '❤️',
  'love': '❤️',
  '爱心': '❤️',
  '流泪': '😢',
  'sad': '😢',
  '闭嘴': '🤐',
  '睡': '😴',
  '大哭': '😭',
  '尴尬': '😅',
  '鼓掌': '👏',
  'clap': '👏',
  '打招呼': '👋',
  '握手': '🤝',
  '胜利': '✌️',
  '向左': '⬅️',
  '向右': '➡️',
  '向上': '⬆️',
  '向下': '⬇️',
  '来呀': '👉',
  '一点点': '🤏',
  '捏住': '🤏',
  '比心': '🫶',
  '加油干': '💪',
  '调皮': '😜',
  '大笑': '😂',
  'laugh': '😂',
  'joy': '😂',
  '惊讶': '😮',
  'surprise': '😮',
  'wow': '😮',
  '流汗': '😅',
  '广播': '📢',
  '自信': '😎',
  '你强': '💪',
  '怒吼': '😤',
  '惊愕': '😱',
  '疑问': '❓',
  '偷笑': '🤭',
  '无聊': '😐',
  '加油': '💪',
  '快哭了': '🥹',
  '吐': '🤮',
  '晕': '😵',
  '摸摸': '🤗',
  '飞吻': '😘',
  '跳舞': '💃',
  '鄙视': '🙄',
  '嘘': '🤫',
  '思考': '🤔',
  'thinking': '🤔',
  '亲亲': '😘',
  '无奈': '😮‍💨',
  '感冒': '🤒',
  '对不起': '🙇',
  '再见': '👋',
  '投降': '🙌',
  '哼': '😤',
  '欠扁': '😠',
  '可怜': '🥺',
  '舒服': '😌',
  '财迷': '🤑',
  '迷惑': '😕',
  '委屈': '😣',
  '灵感': '💡',
  '天使': '😇',
  '鬼脸': '😝',
  '凄凉': '😔',
  '郁闷': '😞',
  '坏笑': '😏',
  '算账': '🧮',
  'pk': '⚔️',
  '忍者': '🥷',
  '衰': '😩',
  '炸弹': '💣',
  '笑哭': '😂',
  '嘿嘿': '😏',
  '捂脸哭': '😭',
  '呲牙': '😁',
  '吃瓜': '🍉',
  '彩虹': '🌈',
  '耶': '✌️',
  '发怒': '😡',
  'angry': '😡',
  '捂眼睛': '🙈',
  '推眼镜': '🤓',
  '脑暴': '🧠',
  '冷笑': '😏',
  '快来': '🏃',
  '收到': '🫡',
  '费解': '🤨',
  '恭喜': '🎉',
  '裂开': '🫠',
  '黑眼圈': '😵‍💫',
  '一团乱麻': '🌀',
  '白眼': '🙄',
  '回头': '👀',
  '惊喜': '🤩',
  '开心': '😄',
  '热': '🥵',
  '敲打': '🔨',
  '捧脸': '🥹',
  'get': '✅',
  '客服': '🧑‍💻',
  'ar': '🥽',
  '小蜜蜂': '🐝',
  '虎虎生威': '🐯',
  '兔飞猛进': '🐰',
  '龙头老大': '🐲',
  '蛇来运转': '🐍',
  '马上来财': '🐴',
  '专注': '🎯',
  '在吗': '❓',
  '退退退': '🛡️',
  '弹射下班': '🚀',
  '这边请': '👉',
  'yyds': '👑',
  '向右看': '👀',
  '向左看': '👀',
  '洪荒之力': '⚡',
  '王之蔑视': '👑',
  '一脸苦笑': '😅',
  '等一等': '⏳',
  '忙疯了': '🤯',
  '让人头大': '🤦',
  '抱抱': '🤗',
  '举手': '🙋',
  '开车': '🚗',
  '抱大腿': '🦵',
  '跪了': '🧎',
  '选我': '🙋',
  '元气满满': '✨',
  '会议': '📅',
  '猫咪': '🐱',
  '鲜花': '🌸',
  '嘴唇': '👄',
  '心碎': '💔',
  '生日快乐': '🎂',
  '礼物': '🎁',
  '撒花': '🎉',
  '承让': '🙏',
  '三多': '🎊',
  '二哈': '🐕',
  '干杯': '🍻',
  'beer': '🍻',
  '咖啡': '☕',
  'coffee': '☕',
  '奶茶': '🧋',
  '茶': '🍵',
  'okr': '📈',
  'kpi': '📊',
  '100分': '💯',
  '对勾': '✅',
  'done': '✅',
  '打叉': '❌',
  '气泡': '💬',
  '加一': '➕',
  '静音': '🔇',
  '时间': '⏰',
  '手机': '📱',
  '废纸篓': '🗑️',
  '表格': '📊',
  '演示': '🖥️',
  '文档': '📄',
  '邮件': '✉️',
  '火箭': '🚀',
  '高铁': '🚄',
  '出差': '🧳',
  '钉子': '📌',
  '公文包': '💼',
  '地球': '🌍',
  '碳减排': '♻️',
  '回收标志': '♻️',
  '幼苗': '🌱',
  '红包': '🧧',
  '恭喜发财': '🧧',
  '定胜': '🏆',
  '平安健康': '🫶',
  '火': '🔥',
  '休假': '🏖️',
  '鸡腿': '🍗',
  '月饼': '🥮',
};

final RegExp _dingtalkMessageEmotionPattern = RegExp(
  r'\[([^\[\]\r\n]{1,24})\](?!\()|【([^【】\r\n]{1,24})】',
);

/// 将消息正文中已知的钉钉表情标记转换为 Emoji，未知标记保留原文。
String normalizeDingTalkMessageEmotions(Object? value) {
  final text = _normalizedDingTalkString(value);
  if (text.isEmpty) return '';
  return text.replaceAllMapped(_dingtalkMessageEmotionPattern, (match) {
    final name = (match.group(1) ?? match.group(2) ?? '').trim();
    final key = name.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    return _dingtalkReactionEmojiMap[key] ?? match.group(0)!;
  });
}

/// 清理 DWS 生成的消息投影字段，并统一正文中的钉钉表情标记。
String normalizeDingTalkMessageContent(Object? value) =>
    normalizeDingTalkMessageEmotions(
      _removeDingTalkDuplicatedLinkProjection(value),
    );

/// 移除钉钉媒体投影标记，但保留同一条消息中的真实文本正文。
///
/// 例如 `[图片] 坏菜了，我也` 只保留 `坏菜了，我也`；纯图片投影会返回空串，
/// 由消息卡片根据媒体列表渲染附件，不再把投影标记当作正文历史。
String stripDingTalkMediaPlaceholder(Object? value) {
  var text = normalizeDingTalkMessageContent(value);
  if (text.isEmpty || text.toLowerCase() == 'null' || text == '[null]') {
    return '';
  }
  if (parseDingTalkDwsFileProjection(text) != null) return '';
  final hasMediaProjection = _dingtalkMediaPlaceholderPattern.hasMatch(text);
  text = text.replaceAll(_dingtalkMediaPlaceholderPattern, ' ');
  if (hasMediaProjection) {
    text = text.replaceFirst(_dwsMediaDownloadHintPattern, ' ');
  }
  return text.replaceAll(_dingtalkWhitespacePattern, ' ').trim();
}

/// 清理媒体投影文本；投影后只剩附件名时同样视为无正文。
String normalizeDingTalkMediaText(
  Object? value,
  Iterable<DingTalkGatewayMedia> media,
) {
  final items = media.toList(growable: false);
  if (items.isEmpty) return normalizeDingTalkMessageContent(value);
  final raw = normalizeDingTalkMessageContentForComparison(value);
  final summary = items.map((item) => '[${item.displayName}]').join(' ');
  if (raw == normalizeDingTalkMessageContentForComparison(summary)) return '';
  final text = stripDingTalkMediaPlaceholder(value);
  final normalized = normalizeDingTalkMessageContentForComparison(text);
  if (normalized.isEmpty) return '';
  for (final item in items) {
    final name = normalizeDingTalkMessageContentForComparison(item.name);
    if (name.isNotEmpty && normalized == name) return '';
  }
  return text;
}

/// 将钉钉表情名称转换为标准 Emoji，未知名称保留为短文本兜底。
String normalizeDingTalkReaction(Object? value) {
  var normalized = _normalizedDingTalkString(value);
  if (normalized.isEmpty) return '';
  final bracketed =
      normalized.length >= 2 &&
      ((normalized.startsWith('[') && normalized.endsWith(']')) ||
          (normalized.startsWith('【') && normalized.endsWith('】')));
  if (bracketed) {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  if (normalized.isEmpty) return '';
  final key = normalized.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  final emoji = _dingtalkReactionEmojiMap[key];
  if (emoji != null) return emoji;
  return String.fromCharCodes(normalized.runes.take(24));
}

const int kDingTalkMaxReactionTypes = 12;

/// 解析钉钉消息查询结果中的全部贴表情，兼容新旧字段和嵌套结构。
List<String> parseDingTalkMessageReactions(Map<String, Object?> message) {
  final result = <String>[];

  void visit(Object? value, int depth) {
    if (value == null ||
        depth > 4 ||
        result.length >= kDingTalkMaxReactionTypes) {
      return;
    }
    if (value is List) {
      for (final item in value) {
        visit(item, depth + 1);
        if (result.length >= kDingTalkMaxReactionTypes) return;
      }
      return;
    }
    if (value is Map) {
      final map = stringKeyedMapFromValue(value);
      for (final key in const <String>[
        'emotionReplyList',
        'emotion_reply_list',
        'reactions',
        'reactionList',
        'reaction_list',
        'reaction',
        'emoji',
        'emoji_code',
        'emojiCode',
        'reaction_text',
        'reactionText',
        'reaction_name',
        'reactionName',
        'reaction_type',
        'reactionType',
        'type',
        'value',
        'content',
      ]) {
        if (map.containsKey(key)) visit(map[key], depth + 1);
      }
      return;
    }
    final reaction = normalizeDingTalkReaction(value);
    if (reaction.isNotEmpty && !result.contains(reaction)) {
      result.add(reaction);
    }
  }

  visit(<Object?>[
    message['emotionReplyList'],
    message['emotion_reply_list'],
    message['reactions'],
    message['reactionList'],
    message['reaction_list'],
    message['reaction'],
  ], 0);
  return result.toList(growable: false);
}

/// 判断钉钉贴表情是否为 Emoji，供消息卡片选择紧凑的文本样式。
bool isDingTalkReactionEmoji(Object? value) {
  final normalized = normalizeDingTalkReaction(value);
  if (normalized.isEmpty) return false;
  return normalized.runes.any(
    (rune) =>
        rune >= 0x1F000 && rune <= 0x1FAFF ||
        rune >= 0x2300 && rune <= 0x23FF ||
        rune >= 0x2600 && rune <= 0x27BF ||
        rune >= 0x2B00 && rune <= 0x2BFF ||
        rune == 0x00A9 ||
        rune == 0x00AE ||
        rune == 0x203C ||
        rune == 0x2049 ||
        rune == 0x2122 ||
        rune == 0x2139,
  );
}

/// 统一清理钉钉媒体资源标识。
///
/// 历史消息内容可能以 `[图片消息](mediaId=...)` 的投影形式保存，
/// 旧版本会把 Markdown 右括号一并写入资源 ID。所有进入下载链路的
/// 资源都应经过此方法，避免同一资源产生多个缓存键或调用无效参数。
String normalizeDingTalkResourceId(Object? value) {
  var text = _normalizedDingTalkString(value);
  while (text.endsWith(')') || text.endsWith(']')) {
    text = text.substring(0, text.length - 1).trimRight();
  }
  return text;
}

const String _dwsFileProjectionPrefix = '[文件] ';
const String _dwsFileProjectionSuffix = ' 注意：如需下载使用dws drive download命令下载';
final RegExp _dwsFileProjectionIdSeparator = RegExp(
  r'\sfileId\s*[:：]\s*',
  caseSensitive: false,
);

/// 解析 DWS 消息列表返回的文件投影文本，仅接受完整固定格式，避免误判普通聊天内容。
({String name, String resourceId})? parseDingTalkDwsFileProjection(
  Object? value,
) {
  final text = normalizeDingTalkMessageContentForComparison(value);
  if (!text.startsWith(_dwsFileProjectionPrefix) ||
      !text.endsWith(_dwsFileProjectionSuffix)) {
    return null;
  }
  final body = text.substring(
    _dwsFileProjectionPrefix.length,
    text.length - _dwsFileProjectionSuffix.length,
  );
  final separators = _dwsFileProjectionIdSeparator.allMatches(body).toList();
  if (separators.length != 1) return null;
  final separator = separators.single;
  final name = body.substring(0, separator.start).trim();
  final resourceId = normalizeDingTalkResourceId(body.substring(separator.end));
  if (name.isEmpty ||
      name.length > 1024 ||
      resourceId.isEmpty ||
      resourceId.length > 1024 ||
      resourceId.contains(RegExp(r'\s'))) {
    return null;
  }
  return (name: name, resourceId: resourceId);
}

/// 判断资源标识是否只是普通链接的查询参数，而不是媒体消息资源。
bool isDingTalkResourceIdInUrlQuery(
  Object? value,
  String resourceId, {
  required DingTalkMediaResourceType resourceType,
}) {
  final normalizedId = normalizeDingTalkResourceId(resourceId);
  final raw = _normalizedDingTalkString(value);
  if (normalizedId.isEmpty || raw.isEmpty) return false;
  final keys = resourceType == DingTalkMediaResourceType.fileId
      ? const <String>{'fileid', 'file_id'}
      : const <String>{'mediaid', 'media_id'};
  final urlPattern = RegExp(
    r'''(?:https?|dingtalk)://[^\s<>()\[\]{}"'\\]+''',
    caseSensitive: false,
  );
  for (final match in urlPattern.allMatches(raw)) {
    var url = match.group(0) ?? '';
    url = url.replaceFirst(RegExp(r'''[)\]}\>"'，。！？,.;]+$'''), '');
    final uri = Uri.tryParse(url);
    if (uri == null) continue;
    for (final entry in uri.queryParameters.entries) {
      if (!keys.contains(entry.key.toLowerCase())) continue;
      if (normalizeDingTalkResourceId(entry.value) == normalizedId) {
        return true;
      }
    }
  }
  return false;
}

/// 统一清理钉钉开放消息标识。
///
/// DWS 的扁平事件和消息列表都返回开放消息 ID，但旧版本的事件封装
/// 偶尔会把 JSON/Markdown 投影的右括号带入标识，导致事件无法匹配本地消息。
String normalizeDingTalkMessageId(Object? value) {
  var text = _normalizedDingTalkString(value);
  while (text.length >= 2 &&
      ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith("'") && text.endsWith("'")))) {
    text = text.substring(1, text.length - 1).trim();
  }
  while (text.endsWith(')') || text.endsWith(']')) {
    text = text.substring(0, text.length - 1).trimRight();
  }
  return text;
}

enum DingTalkConversationType { group, direct }

enum DingTalkResponseMode {
  allowlist('allowlist'),
  all('all');

  const DingTalkResponseMode(this.storageValue);

  final String storageValue;

  static DingTalkResponseMode fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    return values.firstWhere(
      (item) => item.storageValue == normalized,
      orElse: () => DingTalkResponseMode.allowlist,
    );
  }
}

enum DingTalkGatewayMessageRole { user, assistant }

const int _maxDingTalkAutomaticReplyPayloadCharacters = 64 * 1024;
const int _maxDingTalkAutomaticReplySegments = 32;
const int _maxDingTalkAutomaticReplyActions = 8;
const int _maxDingTalkAutomaticReplyJsonCandidates = 32;

enum DingTalkGatewayMessageType {
  text('text'),
  automaticReply('automatic_reply');

  const DingTalkGatewayMessageType(this.storageValue);

  final String storageValue;

  static DingTalkGatewayMessageType fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    return values.firstWhere(
      (item) => item.storageValue == normalized,
      orElse: () => DingTalkGatewayMessageType.text,
    );
  }
}

@immutable
class DingTalkAutomaticReplyTextSegment {
  const DingTalkAutomaticReplyTextSegment({
    required this.text,
    this.emphasized = false,
  });

  factory DingTalkAutomaticReplyTextSegment.fromJson(
    Map<String, Object?> json,
  ) {
    final text = '${json['text'] ?? ''}';
    if (text.trim().isEmpty) {
      throw const FormatException('钉钉自动回复文本为空。');
    }
    return DingTalkAutomaticReplyTextSegment(
      text: text,
      emphasized: boolFromValue(json['emphasized']),
    );
  }

  final String text;
  final bool emphasized;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'emphasized': emphasized,
  };
}

@immutable
class DingTalkAutomaticReplyAction {
  const DingTalkAutomaticReplyAction({required this.label, required this.url});

  factory DingTalkAutomaticReplyAction.fromJson(Map<String, Object?> json) {
    final label = '${json['label'] ?? ''}'.trim();
    final url = '${json['url'] ?? ''}'.trim();
    if (label.isEmpty || url.isEmpty) {
      throw const FormatException('钉钉自动回复操作数据不完整。');
    }
    return DingTalkAutomaticReplyAction(label: label, url: url);
  }

  final String label;
  final String url;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'url': url,
  };
}

@immutable
class DingTalkAutomaticReplyCard {
  const DingTalkAutomaticReplyCard({
    required this.title,
    required this.textSegments,
    required this.actions,
    this.privateOnly = false,
    this.nativeType = '',
  });

  factory DingTalkAutomaticReplyCard.fromJson(Map<String, Object?> json) {
    final title = '${json['title'] ?? ''}'.trim();
    final textSegments =
        (json['text_segments'] is List
                ? json['text_segments'] as List
                : const <Object?>[])
            .take(_maxDingTalkAutomaticReplySegments)
            .whereType<Map>()
            .map((item) {
              try {
                return DingTalkAutomaticReplyTextSegment.fromJson(
                  stringKeyedMapFromValue(item),
                );
              } on FormatException {
                return null;
              }
            })
            .whereType<DingTalkAutomaticReplyTextSegment>()
            .toList(growable: false);
    final actions =
        (json['actions'] is List ? json['actions'] as List : const <Object?>[])
            .take(_maxDingTalkAutomaticReplyActions)
            .whereType<Map>()
            .map((item) {
              try {
                return DingTalkAutomaticReplyAction.fromJson(
                  stringKeyedMapFromValue(item),
                );
              } on FormatException {
                return null;
              }
            })
            .whereType<DingTalkAutomaticReplyAction>()
            .toList(growable: false);
    if (title.isEmpty || textSegments.isEmpty && actions.isEmpty) {
      throw const FormatException('钉钉自动回复卡片数据不完整。');
    }
    return DingTalkAutomaticReplyCard(
      title: title,
      textSegments: textSegments,
      actions: actions,
      privateOnly: boolFromValue(json['private_only']),
      nativeType: '${json['native_type'] ?? ''}'.trim(),
    );
  }

  final String title;
  final List<DingTalkAutomaticReplyTextSegment> textSegments;
  final List<DingTalkAutomaticReplyAction> actions;
  final bool privateOnly;
  final String nativeType;

  String get plainText => textSegments.map((item) => item.text).join().trim();

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'text_segments': textSegments
        .map((item) => item.toJson())
        .toList(growable: false),
    'actions': actions.map((item) => item.toJson()).toList(growable: false),
    'private_only': privateOnly,
    'native_type': nativeType,
  };
}

DingTalkAutomaticReplyCard? parseDingTalkAutomaticReplyCard(
  Object? value, {
  String nativeType = '',
}) {
  final structured = value is Map || value is List;
  final raw = structured ? jsonEncode(value) : _normalizedDingTalkString(value);
  if (raw.isEmpty ||
      structured && raw.length > _maxDingTalkAutomaticReplyPayloadCharacters) {
    return null;
  }
  final values = structured
      ? <Object?>[value]
      : _decodeDingTalkEmbeddedJsonValues(raw);
  if (values.isEmpty) return null;
  var title = '';
  final segments = <DingTalkAutomaticReplyTextSegment>[];
  final actions = <DingTalkAutomaticReplyAction>[];

  void visit(Object? current, int depth) {
    if (depth > 6) return;
    if (current is String) {
      for (final child in _decodeDingTalkEmbeddedJsonValues(current)) {
        visit(child, depth + 1);
      }
      return;
    }
    if (current is List) {
      for (final child in current.take(64)) {
        visit(child, depth + 1);
      }
      return;
    }
    if (current is! Map) return;
    final map = stringKeyedMapFromValue(current);
    final type = '${map['type'] ?? ''}'.trim().toLowerCase();
    if (type == 'markdown' && map['text'] is Map) {
      final text = stringKeyedMapFromValue(map['text']);
      final items = text['items'];
      if (items is List) {
        for (final item
            in items
                .take(_maxDingTalkAutomaticReplySegments)
                .whereType<Map>()) {
          final part = stringKeyedMapFromValue(item);
          if ('${part['type'] ?? ''}'.trim().toLowerCase() != 'text') {
            continue;
          }
          final data = part['data'] is Map
              ? stringKeyedMapFromValue(part['data'])
              : const <String, Object?>{};
          final style = part['style'] is Map
              ? stringKeyedMapFromValue(part['style'])
              : const <String, Object?>{};
          final textValue = '${data['text'] ?? ''}';
          if (textValue.trim().isEmpty) continue;
          segments.add(
            DingTalkAutomaticReplyTextSegment(
              text: textValue,
              emphasized:
                  boolFromValue(style['bold']) ||
                  '${style['lightColor'] ?? style['darkColor'] ?? ''}'
                      .trim()
                      .isNotEmpty,
            ),
          );
        }
      }
    } else if (type == 'action' && map['actions'] is List) {
      for (final item
          in (map['actions'] as List)
              .take(_maxDingTalkAutomaticReplyActions)
              .whereType<Map>()) {
        final action = stringKeyedMapFromValue(item);
        if ('${action['status'] ?? 'normal'}'.trim().toLowerCase() !=
            'normal') {
          continue;
        }
        final label = action['label'] is Map
            ? '${stringKeyedMapFromValue(action['label'])['text'] ?? ''}'.trim()
            : '';
        final url = action['url'] is Map
            ? '${stringKeyedMapFromValue(action['url'])['all'] ?? ''}'.trim()
            : '';
        if (label.isEmpty || url.isEmpty) continue;
        actions.add(DingTalkAutomaticReplyAction(label: label, url: url));
      }
    }
    final rawTitle = map['title'];
    if (title.isEmpty && rawTitle is Map) {
      title = '${stringKeyedMapFromValue(rawTitle)['text'] ?? ''}'.trim();
    }
    for (final child in map.values) {
      if (child is Map || child is List || child is String) {
        visit(child, depth + 1);
      }
    }
  }

  for (final item in values) {
    visit(item, 0);
  }
  if (!title.contains('自动回复') || segments.isEmpty && actions.isEmpty) {
    return null;
  }
  final normalizedNativeType = nativeType.trim().isNotEmpty
      ? nativeType.trim()
      : RegExp(r'(^|\n)\s*custom_link\s*($|\n)').hasMatch(raw)
      ? 'custom_link'
      : '';
  return DingTalkAutomaticReplyCard(
    title: title,
    textSegments: segments.toList(growable: false),
    actions: actions.toList(growable: false),
    privateOnly: raw.contains('仅你和对方可见'),
    nativeType: normalizedNativeType,
  );
}

List<Object?> _decodeDingTalkEmbeddedJsonValues(String raw) {
  final source = raw.length > _maxDingTalkAutomaticReplyPayloadCharacters
      ? raw.substring(0, _maxDingTalkAutomaticReplyPayloadCharacters)
      : raw;
  final values = <Object?>[];
  var attempts = 0;
  for (
    var start = 0;
    start < source.length &&
        values.length < _maxDingTalkAutomaticReplyActions &&
        attempts < _maxDingTalkAutomaticReplyJsonCandidates;
    start++
  ) {
    final opening = source.codeUnitAt(start);
    if (opening != 0x5B && opening != 0x7B) continue;
    attempts++;
    final expectedClosings = <int>[opening == 0x5B ? 0x5D : 0x7D];
    var quoted = false;
    var escaped = false;
    for (var end = start + 1; end < source.length; end++) {
      final code = source.codeUnitAt(end);
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5C) {
          escaped = true;
        } else if (code == 0x22) {
          quoted = false;
        }
        continue;
      }
      if (code == 0x22) {
        quoted = true;
      } else if (code == 0x5B || code == 0x7B) {
        expectedClosings.add(code == 0x5B ? 0x5D : 0x7D);
      } else if (code == 0x5D || code == 0x7D) {
        if (expectedClosings.isEmpty || expectedClosings.last != code) break;
        expectedClosings.removeLast();
        if (expectedClosings.isNotEmpty) continue;
        try {
          values.add(jsonDecode(source.substring(start, end + 1)));
          start = end;
        } on FormatException {
          // 普通文本中的括号不是卡片 JSON，继续扫描后续内容。
        }
        break;
      }
    }
  }
  return values;
}

enum DingTalkOverloadStrategy {
  queue('queue'),
  reject('reject'),
  drop('drop');

  const DingTalkOverloadStrategy(this.storageValue);

  final String storageValue;

  static DingTalkOverloadStrategy fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    return values.firstWhere(
      (item) => item.storageValue == normalized,
      orElse: () => DingTalkOverloadStrategy.queue,
    );
  }
}

enum DingTalkMessageAiResponseState {
  none('none'),
  queued('queued'),
  responding('responding'),
  responded('responded'),
  rejected('rejected'),
  dropped('dropped'),
  cancelled('cancelled'),
  failed('failed');

  const DingTalkMessageAiResponseState(this.storageValue);

  final String storageValue;

  static DingTalkMessageAiResponseState fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    return values.firstWhere(
      (item) => item.storageValue == normalized,
      orElse: () => DingTalkMessageAiResponseState.none,
    );
  }
}

enum DingTalkGatewayMessageFeedback {
  liked('liked'),
  needsImprovement('needs_improvement');

  const DingTalkGatewayMessageFeedback(this.storageValue);

  final String storageValue;

  static DingTalkGatewayMessageFeedback? fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    for (final item in values) {
      if (item.storageValue == normalized) return item;
    }
    return null;
  }
}

enum DingTalkGatewayEventType { message, read, recall, reaction }

@immutable
class DingTalkGatewayEvent {
  const DingTalkGatewayEvent({
    required this.type,
    required this.messageId,
    required this.conversationId,
    required this.conversationType,
    this.message,
    this.reaction = '',
    this.reactionRemoved = false,
  });

  final DingTalkGatewayEventType type;
  final String messageId;
  final String conversationId;
  final DingTalkConversationType conversationType;
  final DingTalkGatewayMessage? message;
  final String reaction;
  final bool reactionRemoved;
}

/// 钉钉消息中的媒体资源类型。file 覆盖钉钉文件、压缩包等非预览资源。
enum DingTalkMediaKind { image, video, audio, file }

enum DingTalkMediaResourceType { mediaId, fileId }

/// DWS 当前按单文件消息发送本地附件，应用侧将多附件拆分为连续文件消息。
const int kDingTalkMessageAttachmentLimit = 6;
const int kDingTalkMessageAttachmentMaxBytes = 512 * kBytesPerMiB;

extension DingTalkMediaKindX on DingTalkMediaKind {
  String get storageValue => name;

  bool get isPreviewable => this != DingTalkMediaKind.file;

  static DingTalkMediaKind fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    if (normalized.contains('image') ||
        normalized.contains('photo') ||
        normalized.contains('picture')) {
      return DingTalkMediaKind.image;
    }
    if (normalized.contains('video')) return DingTalkMediaKind.video;
    if (normalized.contains('audio') || normalized.contains('voice')) {
      return DingTalkMediaKind.audio;
    }
    return DingTalkMediaKind.file;
  }

  static DingTalkMediaKind fromFileName(String value) {
    return switch (p.extension(value).toLowerCase()) {
      '.png' ||
      '.jpg' ||
      '.jpeg' ||
      '.gif' ||
      '.webp' ||
      '.bmp' ||
      '.heic' ||
      '.svg' => DingTalkMediaKind.image,
      '.mp4' ||
      '.mov' ||
      '.m4v' ||
      '.webm' ||
      '.mkv' ||
      '.avi' => DingTalkMediaKind.video,
      '.mp3' ||
      '.wav' ||
      '.m4a' ||
      '.aac' ||
      '.ogg' ||
      '.opus' ||
      '.flac' => DingTalkMediaKind.audio,
      _ => DingTalkMediaKind.file,
    };
  }
}

@immutable
class DingTalkGatewayMedia {
  const DingTalkGatewayMedia({
    required this.resourceId,
    this.messageId = '',
    this.conversationId = '',
    this.resourceType = DingTalkMediaResourceType.mediaId,
    this.kind = DingTalkMediaKind.file,
    this.name = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.durationMs,
    this.localPath = '',
  });

  factory DingTalkGatewayMedia.fromJson(Map<String, Object?> json) {
    final resourceId = normalizeDingTalkResourceId(
      json['resource_id'] ?? json['media_id'] ?? json['file_id'],
    );
    if (resourceId.isEmpty) {
      throw const FormatException('钉钉媒体资源标识不完整。');
    }
    final rawType = _normalizedDingTalkString(
      json['resource_type'] ?? (json['file_id'] != null ? 'fileId' : 'mediaId'),
    ).toLowerCase();
    final name = _normalizedDingTalkString(json['name'] ?? json['file_name']);
    final mimeType = _normalizedDingTalkString(
      json['mime_type'] ?? json['mimeType'],
    );
    var kind = DingTalkMediaKindX.fromStorage(
      json['kind'] ?? json['media_type'],
    );
    if (kind == DingTalkMediaKind.file && name.isNotEmpty) {
      kind = DingTalkMediaKindX.fromFileName(name);
    }
    if (kind == DingTalkMediaKind.file && mimeType.isNotEmpty) {
      kind = DingTalkMediaKindX.fromStorage(mimeType);
    }
    return DingTalkGatewayMedia(
      resourceId: resourceId,
      messageId: _normalizedDingTalkString(json['message_id']),
      conversationId: _normalizedDingTalkString(json['conversation_id']),
      resourceType: rawType == 'fileid'
          ? DingTalkMediaResourceType.fileId
          : DingTalkMediaResourceType.mediaId,
      kind: kind,
      name: name,
      mimeType: mimeType,
      sizeBytes: _nonNegativeInt(json['size_bytes'] ?? json['size']),
      durationMs: _nullableNonNegativeInt(
        json['duration_ms'] ?? json['duration'],
      ),
      localPath: _normalizedDingTalkString(json['local_path']),
    );
  }

  final String resourceId;
  final String messageId;
  final String conversationId;
  final DingTalkMediaResourceType resourceType;
  final DingTalkMediaKind kind;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final int? durationMs;
  final String localPath;

  String get displayName {
    final normalized = _normalizedDingTalkString(name);
    if (normalized.isNotEmpty) return normalized;
    return switch (kind) {
      DingTalkMediaKind.image => '图片',
      DingTalkMediaKind.video => '视频',
      DingTalkMediaKind.audio => '语音',
      DingTalkMediaKind.file => '文件',
    };
  }

  DingTalkGatewayMedia copyWith({
    String? resourceId,
    String? messageId,
    String? conversationId,
    DingTalkMediaResourceType? resourceType,
    DingTalkMediaKind? kind,
    String? name,
    String? mimeType,
    int? sizeBytes,
    int? durationMs,
    String? localPath,
  }) {
    return DingTalkGatewayMedia(
      resourceId: resourceId ?? this.resourceId,
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      resourceType: resourceType ?? this.resourceType,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      durationMs: durationMs ?? this.durationMs,
      localPath: localPath ?? this.localPath,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'resource_id': resourceId,
    'message_id': messageId,
    'conversation_id': conversationId,
    'resource_type': resourceType.name,
    'kind': kind.storageValue,
    'name': name,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'duration_ms': durationMs,
    'local_path': localPath,
  };

  static int _nonNegativeInt(Object? value) =>
      _nullableNonNegativeInt(value) ?? 0;

  static int? _nullableNonNegativeInt(Object? value) {
    final parsed = int.tryParse('$value');
    return parsed != null && parsed >= 0 ? parsed : null;
  }
}

enum DingTalkReminderMode { none, inApp, sound }

/// 允许同步回显到钉钉的 AI 消息卡片类型。
enum DingTalkResponseEchoType {
  thinking('thinking'),
  process('process'),
  toolCall('tool_call'),
  finalResponse('final_response');

  const DingTalkResponseEchoType(this.storageValue);

  final String storageValue;

  static DingTalkResponseEchoType? fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    for (final item in values) {
      if (item.storageValue == normalized || item.name == normalized) {
        return item;
      }
    }
    return null;
  }
}

class DingTalkConversationTarget {
  const DingTalkConversationTarget({
    required this.id,
    required this.title,
    required this.type,
    this.subtitle = '',
    this.aliases = const <String>[],
    this.userId = '',
    this.openDingTalkId = '',
  });

  factory DingTalkConversationTarget.fromJson(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException('钉钉会话目标数据不完整。');
    }
    return DingTalkConversationTarget(
      id: id,
      title: title,
      type: DingTalkConversationType.values.firstWhere(
        (item) => item.name == '${json['type'] ?? ''}',
        orElse: () => DingTalkConversationType.direct,
      ),
      subtitle: '${json['subtitle'] ?? ''}'.trim(),
      aliases: _stringList(json['aliases']),
      userId: '${json['user_id'] ?? ''}'.trim(),
      openDingTalkId: '${json['open_dingtalk_id'] ?? ''}'.trim(),
    );
  }

  final String id;
  final String title;
  final DingTalkConversationType type;
  final String subtitle;
  final List<String> aliases;
  final String userId;
  final String openDingTalkId;

  Iterable<String> get identifiers sync* {
    yield id;
    if (userId.isNotEmpty) yield userId;
    if (openDingTalkId.isNotEmpty) yield openDingTalkId;
    yield* aliases;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'type': type.name,
    'subtitle': subtitle,
    'aliases': aliases,
    'user_id': userId,
    'open_dingtalk_id': openDingTalkId,
  };

  static List<String> _stringList(Object? value) => stringListFromValue(value)
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .take(8)
      .toList(growable: false);
}

class DingTalkGatewaySettings {
  const DingTalkGatewaySettings({
    this.pollIntervalSeconds = defaultPollIntervalSeconds,
    this.responseWorkerCount = defaultResponseWorkerCount,
    this.overloadStrategy = DingTalkOverloadStrategy.queue,
    this.reminderMode = DingTalkReminderMode.inApp,
    this.responseMode = DingTalkResponseMode.allowlist,
    this.responseModelKey = '',
    this.workingDirectory = '',
    this.fullAccessPermission = false,
    this.templateId = 'default',
    this.allowedMcpServerNames = const <String>[],
    this.allowedSkillNames = const <String>[],
    this.allowedMemoryIds = const <String>[],
    this.allowedInstructionIds = const <String>[],
    this.allowedKnowledgeBaseSourceIds = const <String>[],
    this.allowedDingTalkDwsCommandIds = const <String>[],
    this.enabledMultimodalCapabilities =
        const <AiDingTalkMultimodalCapability>{},
    this.imageGenerationModelKey = '',
    this.videoGenerationModelKey = '',
    this.audioGenerationModelKey = '',
    this.allowedGroupTargets = const <DingTalkConversationTarget>[],
    this.allowedContactTargets = const <DingTalkConversationTarget>[],
    this.responseEchoTypes = const <DingTalkResponseEchoType>[
      DingTalkResponseEchoType.finalResponse,
    ],
  });

  factory DingTalkGatewaySettings.fromJson(Map<String, Object?> json) {
    final mode = DingTalkReminderMode.values.firstWhere(
      (item) => item.name == '${json['reminder_mode'] ?? ''}',
      orElse: () => DingTalkReminderMode.inApp,
    );
    return DingTalkGatewaySettings(
      pollIntervalSeconds: normalizePollIntervalSeconds(
        json['poll_interval_seconds'],
      ),
      responseWorkerCount: normalizeResponseWorkerCount(
        json['response_worker_count'],
      ),
      overloadStrategy: DingTalkOverloadStrategy.fromStorage(
        json['overload_strategy'],
      ),
      reminderMode: mode,
      responseMode: DingTalkResponseMode.fromStorage(json['response_mode']),
      responseModelKey: '${json['response_model_key'] ?? ''}',
      workingDirectory: '${json['working_directory'] ?? ''}',
      fullAccessPermission: boolFromValue(json['full_access_permission']),
      templateId: '${json['template_id'] ?? 'default'}',
      allowedMcpServerNames: _stringList(json['allowed_mcp_server_names']),
      allowedSkillNames: _stringList(json['allowed_skill_names']),
      allowedMemoryIds: _stringList(json['allowed_memory_ids']),
      allowedInstructionIds: _stringList(json['allowed_instruction_ids']),
      allowedKnowledgeBaseSourceIds: _stringList(
        json['allowed_knowledge_base_source_ids'],
      ),
      allowedDingTalkDwsCommandIds: _stringList(
        json['allowed_dingtalk_dws_command_ids'],
        limit: 1024,
      ),
      enabledMultimodalCapabilities: _multimodalCapabilitySet(
        json['enabled_multimodal_capabilities'],
      ),
      imageGenerationModelKey: '${json['image_generation_model_key'] ?? ''}',
      videoGenerationModelKey: '${json['video_generation_model_key'] ?? ''}',
      audioGenerationModelKey: '${json['audio_generation_model_key'] ?? ''}',
      allowedGroupTargets: _targetList(
        json['allowed_group_targets'],
        DingTalkConversationType.group,
      ),
      allowedContactTargets: _targetList(
        json['allowed_contact_targets'],
        DingTalkConversationType.direct,
      ),
      responseEchoTypes: _responseEchoTypeList(json['response_echo_types']),
    ).normalized();
  }

  static const int defaultPollIntervalSeconds = 3;
  static const int minPollIntervalSeconds = 3;
  static const int maxPollIntervalSeconds = 300;
  static const int defaultResponseWorkerCount = 1;
  static const int minResponseWorkerCount = 1;
  static const int maxResponseWorkerCount = 8;

  final int pollIntervalSeconds;
  final int responseWorkerCount;
  final DingTalkOverloadStrategy overloadStrategy;
  final DingTalkReminderMode reminderMode;
  final DingTalkResponseMode responseMode;
  final String responseModelKey;
  final String workingDirectory;
  final bool fullAccessPermission;
  final String templateId;
  final List<String> allowedMcpServerNames;
  final List<String> allowedSkillNames;
  final List<String> allowedMemoryIds;
  final List<String> allowedInstructionIds;
  final List<String> allowedKnowledgeBaseSourceIds;
  final List<String> allowedDingTalkDwsCommandIds;
  final Set<AiDingTalkMultimodalCapability> enabledMultimodalCapabilities;
  final String imageGenerationModelKey;
  final String videoGenerationModelKey;
  final String audioGenerationModelKey;
  final List<DingTalkConversationTarget> allowedGroupTargets;
  final List<DingTalkConversationTarget> allowedContactTargets;
  final List<DingTalkResponseEchoType> responseEchoTypes;

  bool allowsAutomaticResponseFor(DingTalkConversationTarget target) {
    final targetIdentifiers = target.identifiers
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (targetIdentifiers.isEmpty) return false;
    if (responseMode == DingTalkResponseMode.all) return true;
    final allowedTargets = target.type == DingTalkConversationType.group
        ? allowedGroupTargets
        : allowedContactTargets;
    return allowedTargets.any(
      (item) => item.identifiers.any(targetIdentifiers.contains),
    );
  }

  static int normalizePollIntervalSeconds(Object? value) {
    final parsed = optionalIntegralIntFromValue(value);
    return (parsed ?? defaultPollIntervalSeconds)
        .clamp(minPollIntervalSeconds, maxPollIntervalSeconds)
        .toInt();
  }

  static int normalizeResponseWorkerCount(Object? value) {
    final parsed = optionalIntegralIntFromValue(value);
    if (parsed == null) return defaultResponseWorkerCount;
    return parsed.clamp(minResponseWorkerCount, maxResponseWorkerCount).toInt();
  }

  Duration get pollInterval =>
      Duration(seconds: normalizePollIntervalSeconds(pollIntervalSeconds));

  DingTalkGatewaySettings normalized({
    Iterable<String>? availableMcpServerNames,
    Iterable<String>? availableSkillNames,
    Iterable<String>? availableMemoryIds,
    Iterable<String>? availableInstructionIds,
    Iterable<String>? availableKnowledgeBaseSourceIds,
    Iterable<String>? availableDingTalkDwsCommandIds,
  }) => DingTalkGatewaySettings(
    pollIntervalSeconds: normalizePollIntervalSeconds(pollIntervalSeconds),
    responseWorkerCount: normalizeResponseWorkerCount(responseWorkerCount),
    overloadStrategy: overloadStrategy,
    reminderMode: reminderMode,
    responseMode: responseMode,
    responseModelKey: responseModelKey.trim(),
    workingDirectory: Directory(
      OpenHandPaths.normalizePath(
        workingDirectory,
        defaultPath: OpenHandPaths.applicationDirectoryPath(),
      ),
    ).absolute.path,
    fullAccessPermission: fullAccessPermission,
    templateId: templateId.trim().isEmpty ? 'default' : templateId.trim(),
    allowedMcpServerNames: _normalizeSelection(
      allowedMcpServerNames,
      availableMcpServerNames,
    ),
    allowedSkillNames: _normalizeSelection(
      allowedSkillNames,
      availableSkillNames,
    ),
    allowedMemoryIds: _normalizeSelection(allowedMemoryIds, availableMemoryIds),
    allowedInstructionIds: _normalizeSelection(
      allowedInstructionIds,
      availableInstructionIds,
    ),
    allowedKnowledgeBaseSourceIds: _normalizeSelection(
      allowedKnowledgeBaseSourceIds,
      availableKnowledgeBaseSourceIds,
    ),
    allowedDingTalkDwsCommandIds: _normalizeSelection(
      allowedDingTalkDwsCommandIds,
      availableDingTalkDwsCommandIds,
      limit: 1024,
    ),
    enabledMultimodalCapabilities:
        Set<AiDingTalkMultimodalCapability>.unmodifiable(
          enabledMultimodalCapabilities,
        ),
    imageGenerationModelKey: imageGenerationModelKey.trim(),
    videoGenerationModelKey: videoGenerationModelKey.trim(),
    audioGenerationModelKey: audioGenerationModelKey.trim(),
    allowedGroupTargets: responseMode == DingTalkResponseMode.all
        ? const <DingTalkConversationTarget>[]
        : _normalizeTargets(allowedGroupTargets),
    allowedContactTargets: responseMode == DingTalkResponseMode.all
        ? const <DingTalkConversationTarget>[]
        : _normalizeTargets(allowedContactTargets),
    responseEchoTypes: _normalizeResponseEchoTypes(responseEchoTypes),
  );

  DingTalkGatewaySettings copyWith({
    int? pollIntervalSeconds,
    int? responseWorkerCount,
    DingTalkOverloadStrategy? overloadStrategy,
    DingTalkReminderMode? reminderMode,
    DingTalkResponseMode? responseMode,
    String? responseModelKey,
    String? workingDirectory,
    bool? fullAccessPermission,
    String? templateId,
    List<String>? allowedMcpServerNames,
    List<String>? allowedSkillNames,
    List<String>? allowedMemoryIds,
    List<String>? allowedInstructionIds,
    List<String>? allowedKnowledgeBaseSourceIds,
    List<String>? allowedDingTalkDwsCommandIds,
    Set<AiDingTalkMultimodalCapability>? enabledMultimodalCapabilities,
    String? imageGenerationModelKey,
    String? videoGenerationModelKey,
    String? audioGenerationModelKey,
    List<DingTalkConversationTarget>? allowedGroupTargets,
    List<DingTalkConversationTarget>? allowedContactTargets,
    List<DingTalkResponseEchoType>? responseEchoTypes,
  }) => DingTalkGatewaySettings(
    pollIntervalSeconds: normalizePollIntervalSeconds(
      pollIntervalSeconds ?? this.pollIntervalSeconds,
    ),
    responseWorkerCount: normalizeResponseWorkerCount(
      responseWorkerCount ?? this.responseWorkerCount,
    ),
    overloadStrategy: overloadStrategy ?? this.overloadStrategy,
    reminderMode: reminderMode ?? this.reminderMode,
    responseMode: responseMode ?? this.responseMode,
    responseModelKey: responseModelKey ?? this.responseModelKey,
    workingDirectory: workingDirectory ?? this.workingDirectory,
    fullAccessPermission: fullAccessPermission ?? this.fullAccessPermission,
    templateId: templateId ?? this.templateId,
    allowedMcpServerNames: allowedMcpServerNames ?? this.allowedMcpServerNames,
    allowedSkillNames: allowedSkillNames ?? this.allowedSkillNames,
    allowedMemoryIds: allowedMemoryIds ?? this.allowedMemoryIds,
    allowedInstructionIds: allowedInstructionIds ?? this.allowedInstructionIds,
    allowedKnowledgeBaseSourceIds:
        allowedKnowledgeBaseSourceIds ?? this.allowedKnowledgeBaseSourceIds,
    allowedDingTalkDwsCommandIds:
        allowedDingTalkDwsCommandIds ?? this.allowedDingTalkDwsCommandIds,
    enabledMultimodalCapabilities:
        enabledMultimodalCapabilities ?? this.enabledMultimodalCapabilities,
    imageGenerationModelKey:
        imageGenerationModelKey ?? this.imageGenerationModelKey,
    videoGenerationModelKey:
        videoGenerationModelKey ?? this.videoGenerationModelKey,
    audioGenerationModelKey:
        audioGenerationModelKey ?? this.audioGenerationModelKey,
    allowedGroupTargets: allowedGroupTargets ?? this.allowedGroupTargets,
    allowedContactTargets: allowedContactTargets ?? this.allowedContactTargets,
    responseEchoTypes: responseEchoTypes ?? this.responseEchoTypes,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'poll_interval_seconds': pollIntervalSeconds,
    'response_worker_count': responseWorkerCount,
    'overload_strategy': overloadStrategy.storageValue,
    'reminder_mode': reminderMode.name,
    'response_mode': responseMode.storageValue,
    'response_model_key': responseModelKey,
    'working_directory': workingDirectory,
    'full_access_permission': fullAccessPermission,
    'template_id': templateId,
    'allowed_mcp_server_names': allowedMcpServerNames,
    'allowed_skill_names': allowedSkillNames,
    'allowed_memory_ids': allowedMemoryIds,
    'allowed_instruction_ids': allowedInstructionIds,
    'allowed_knowledge_base_source_ids': allowedKnowledgeBaseSourceIds,
    'allowed_dingtalk_dws_command_ids': allowedDingTalkDwsCommandIds,
    'enabled_multimodal_capabilities': enabledMultimodalCapabilities
        .map((item) => item.storageValue)
        .toList(growable: false),
    'image_generation_model_key': imageGenerationModelKey,
    'video_generation_model_key': videoGenerationModelKey,
    'audio_generation_model_key': audioGenerationModelKey,
    'allowed_group_targets': allowedGroupTargets
        .map((item) => item.toJson())
        .toList(growable: false),
    'allowed_contact_targets': allowedContactTargets
        .map((item) => item.toJson())
        .toList(growable: false),
    'response_echo_types': responseEchoTypes
        .map((item) => item.storageValue)
        .toList(growable: false),
  };

  static List<String> _stringList(Object? value, {int limit = 256}) {
    return stringListFromValue(value)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .take(limit)
        .toList(growable: false);
  }

  static Set<AiDingTalkMultimodalCapability> _multimodalCapabilitySet(
    Object? value,
  ) {
    final rawValues = value is List ? value : <Object?>[value];
    return <AiDingTalkMultimodalCapability>{
      for (final raw in rawValues.take(
        AiDingTalkMultimodalCapability.values.length,
      ))
        if (AiDingTalkMultimodalCapability.fromStorage(raw) case final item?)
          item,
    };
  }

  static List<DingTalkResponseEchoType> _responseEchoTypeList(Object? value) {
    final rawValues = value is List ? value : <Object?>[value];
    final result = <DingTalkResponseEchoType>[];
    final seen = <DingTalkResponseEchoType>{};
    for (final raw in rawValues.take(8)) {
      final type = DingTalkResponseEchoType.fromStorage(raw);
      if (type != null && seen.add(type)) result.add(type);
    }
    return result;
  }

  static List<DingTalkResponseEchoType> _normalizeResponseEchoTypes(
    Iterable<DingTalkResponseEchoType> values,
  ) {
    final result = <DingTalkResponseEchoType>[];
    final seen = <DingTalkResponseEchoType>{};
    for (final type in values) {
      if (seen.add(type)) result.add(type);
    }
    if (result.isEmpty) {
      result.add(DingTalkResponseEchoType.finalResponse);
    }
    return result.toList(growable: false);
  }

  static List<String> _normalizeSelection(
    Iterable<String> values,
    Iterable<String>? available, {
    int limit = 256,
  }) {
    final normalized = _stringList(values, limit: limit);
    if (available == null) return normalized;
    final allowed = available
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    return normalized.where(allowed.contains).toList(growable: false);
  }

  static List<DingTalkConversationTarget> _targetList(
    Object? value,
    DingTalkConversationType expectedType,
  ) {
    if (value is! List) return const <DingTalkConversationTarget>[];
    final result = <DingTalkConversationTarget>[];
    final seen = <String>{};
    for (final item in value.take(128)) {
      if (item is! Map) continue;
      try {
        final target = DingTalkConversationTarget.fromJson(
          stringKeyedMapFromValue(item),
        );
        if (target.type == expectedType && seen.add(target.id)) {
          result.add(target);
        }
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  static List<DingTalkConversationTarget> _normalizeTargets(
    Iterable<DingTalkConversationTarget> values,
  ) {
    final result = <DingTalkConversationTarget>[];
    final seen = <String>{};
    for (final target in values.take(128)) {
      final id = target.id.trim();
      final title = target.title.trim();
      if (id.isEmpty || title.isEmpty || !seen.add('${target.type.name}:$id')) {
        continue;
      }
      final aliases = target.aliases
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty && item != id)
          .toSet()
          .take(8)
          .toList(growable: false);
      result.add(
        DingTalkConversationTarget(
          id: id,
          title: title,
          type: target.type,
          subtitle: target.subtitle.trim(),
          aliases: aliases,
          userId: target.userId.trim(),
          openDingTalkId: target.openDingTalkId.trim(),
        ),
      );
    }
    return result;
  }
}

bool isDingTalkAutomaticResponseCandidate(DingTalkGatewayMessage message) {
  if (message.isAssistant || message.isExcludedFromAiContext) return false;
  return message.conversationType == DingTalkConversationType.direct ||
      message.mentionedCurrentUser;
}

class DingTalkIdentity {
  const DingTalkIdentity({
    this.profile = '',
    this.userId = '',
    this.openDingTalkId = '',
    this.name = '',
  });

  final String profile;
  final String userId;
  final String openDingTalkId;
  final String name;

  String get label => name.trim().isEmpty ? userId : name;
}

@immutable
class DingTalkMessageEditRecord {
  const DingTalkMessageEditRecord({
    required this.content,
    required this.editedAt,
  });

  factory DingTalkMessageEditRecord.fromJson(Map<String, Object?> json) {
    final content = '${json['content'] ?? ''}';
    final editedAt = DateTime.tryParse('${json['edited_at'] ?? ''}');
    if (content.isEmpty || editedAt == null) {
      throw const FormatException('钉钉消息编辑历史数据不完整。');
    }
    return DingTalkMessageEditRecord(content: content, editedAt: editedAt);
  }

  final String content;
  final DateTime editedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'content': content,
    'edited_at': editedAt.toIso8601String(),
  };
}

const int kDingTalkForwardedMessageLimit = 500;

@immutable
class DingTalkQuotedMessage {
  const DingTalkQuotedMessage({
    required this.id,
    required this.content,
    required this.createdAt,
    this.senderName = '',
    this.senderId = '',
    this.media = const <DingTalkGatewayMedia>[],
  });

  factory DingTalkQuotedMessage.fromJson(Map<String, Object?> json) {
    final createdAt = DateTime.tryParse('${json['created_at'] ?? ''}');
    if (createdAt == null) {
      throw const FormatException('钉钉引用消息时间不完整。');
    }
    final id = normalizeDingTalkMessageId(json['id']);
    final rawContent = stripImageSummaryMarkup('${json['content'] ?? ''}');
    final projection = parseDingTalkDwsFileProjection(rawContent);
    final storedMedia = _dingTalkGatewayMediaList(json['media']);
    final media = storedMedia.isNotEmpty || projection == null
        ? storedMedia
        : <DingTalkGatewayMedia>[
            DingTalkGatewayMedia(
              resourceId: projection.resourceId,
              messageId: id,
              resourceType: DingTalkMediaResourceType.fileId,
              kind: DingTalkMediaKindX.fromFileName(projection.name),
              name: projection.name,
            ),
          ];
    final textContent = normalizeDingTalkMediaText(rawContent, media);
    if (id.isEmpty && textContent.isEmpty && media.isEmpty) {
      throw const FormatException('钉钉引用消息内容不完整。');
    }
    return DingTalkQuotedMessage(
      id: id,
      content: textContent.isEmpty
          ? media.map((item) => '[${item.displayName}]').join(' ')
          : textContent,
      createdAt: createdAt,
      senderName: _normalizedDingTalkString(json['sender_name']),
      senderId: _normalizedDingTalkString(json['sender_id']),
      media: media,
    );
  }

  final String id;
  final String content;
  final DateTime createdAt;
  final String senderName;
  final String senderId;
  final List<DingTalkGatewayMedia> media;

  DingTalkQuotedMessage copyWith({List<DingTalkGatewayMedia>? media}) {
    return DingTalkQuotedMessage(
      id: id,
      content: content,
      createdAt: createdAt,
      senderName: senderName,
      senderId: senderId,
      media: media ?? this.media,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'sender_name': senderName,
    'sender_id': senderId,
    'media': media.map((item) => item.toJson()).toList(growable: false),
  };
}

@immutable
class DingTalkForwardedMessage {
  const DingTalkForwardedMessage({
    required this.id,
    required this.content,
    required this.createdAt,
    this.senderName = '',
    this.senderId = '',
    this.media = const <DingTalkGatewayMedia>[],
    this.ignoredForAiContext = false,
  });

  factory DingTalkForwardedMessage.fromJson(Map<String, Object?> json) {
    final createdAt = DateTime.tryParse('${json['created_at'] ?? ''}');
    if (createdAt == null) {
      throw const FormatException('钉钉转发聊天记录时间不完整。');
    }
    final id = normalizeDingTalkMessageId(json['id']);
    final rawContent = stripImageSummaryMarkup('${json['content'] ?? ''}');
    final projection = parseDingTalkDwsFileProjection(rawContent);
    final storedMedia = _dingTalkGatewayMediaList(json['media']);
    final media = storedMedia.isNotEmpty || projection == null
        ? storedMedia
        : <DingTalkGatewayMedia>[
            DingTalkGatewayMedia(
              resourceId: projection.resourceId,
              messageId: id,
              resourceType: DingTalkMediaResourceType.fileId,
              kind: DingTalkMediaKindX.fromFileName(projection.name),
              name: projection.name,
            ),
          ];
    final textContent = normalizeDingTalkMediaText(rawContent, media);
    return DingTalkForwardedMessage(
      id: id,
      content: textContent.isEmpty
          ? media.map((item) => '[${item.displayName}]').join(' ')
          : textContent,
      createdAt: createdAt,
      senderName: _normalizedDingTalkString(json['sender_name']),
      senderId: _normalizedDingTalkString(json['sender_id']),
      media: media,
      ignoredForAiContext: boolFromValue(json['ignored_for_ai_context']),
    );
  }

  final String id;
  final String content;
  final DateTime createdAt;
  final String senderName;
  final String senderId;
  final List<DingTalkGatewayMedia> media;
  final bool ignoredForAiContext;

  DingTalkForwardedMessage copyWith({
    List<DingTalkGatewayMedia>? media,
    bool? ignoredForAiContext,
  }) {
    return DingTalkForwardedMessage(
      id: id,
      content: content,
      createdAt: createdAt,
      senderName: senderName,
      senderId: senderId,
      media: media ?? this.media,
      ignoredForAiContext: ignoredForAiContext ?? this.ignoredForAiContext,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'sender_name': senderName,
    'sender_id': senderId,
    'media': media.map((item) => item.toJson()).toList(growable: false),
    'ignored_for_ai_context': ignoredForAiContext,
  };
}

List<DingTalkGatewayMedia> _dingTalkGatewayMediaList(Object? raw) {
  if (raw is! List) return const <DingTalkGatewayMedia>[];
  final result = <DingTalkGatewayMedia>[];
  final seen = <String>{};
  for (final item in raw.take(12)) {
    if (item is! Map) continue;
    try {
      final media = DingTalkGatewayMedia.fromJson(
        stringKeyedMapFromValue(item),
      );
      if (seen.add('${media.resourceType.name}:${media.resourceId}')) {
        result.add(media);
      }
    } on FormatException {
      continue;
    }
  }
  return result.toList(growable: false);
}

List<DingTalkForwardedMessage> _dingTalkForwardedMessageList(Object? raw) {
  if (raw is! List) return const <DingTalkForwardedMessage>[];
  return raw
      .take(kDingTalkForwardedMessageLimit)
      .whereType<Map>()
      .map((item) {
        try {
          return DingTalkForwardedMessage.fromJson(
            stringKeyedMapFromValue(item),
          );
        } on FormatException {
          return null;
        }
      })
      .whereType<DingTalkForwardedMessage>()
      .toList(growable: false);
}

DingTalkQuotedMessage? _dingTalkQuotedMessage(Object? raw) {
  if (raw is! Map) return null;
  try {
    return DingTalkQuotedMessage.fromJson(stringKeyedMapFromValue(raw));
  } on FormatException {
    return null;
  }
}

class DingTalkGatewayMessage {
  const DingTalkGatewayMessage({
    required this.id,
    required this.conversationId,
    required this.conversationType,
    required this.role,
    required this.content,
    required this.createdAt,
    this.senderName = '',
    this.senderId = '',
    this.conversationTitle = '',
    this.messageType = DingTalkGatewayMessageType.text,
    this.automaticReplyCard,
    this.media = const <DingTalkGatewayMedia>[],
    this.quotedMessage,
    this.forwardedMessages = const <DingTalkForwardedMessage>[],
    this.forwardedMessageCount = 0,
    this.fromSelf = false,
    this.failed = false,
    this.mentionedCurrentUser = false,
    this.readByPeer = false,
    this.aiResponseState = DingTalkMessageAiResponseState.none,
    this.recalled = false,
    this.ignoredForAiContext = false,
    this.reactions = const <String>[],
    this.reactionSnapshotComplete = false,
    this.editHistory = const <DingTalkMessageEditRecord>[],
    this.sourceAiMessageId = '',
    this.responseEchoType,
    this.feedback,
  });

  factory DingTalkGatewayMessage.fromJson(Map<String, Object?> json) {
    final id = normalizeDingTalkMessageId(json['id']);
    final conversationId = '${json['conversation_id'] ?? ''}'.trim();
    final rawContent = stripImageSummaryMarkup('${json['content'] ?? ''}');
    final createdAt = DateTime.tryParse('${json['created_at'] ?? ''}');
    if (id.isEmpty || conversationId.isEmpty || createdAt == null) {
      throw const FormatException('钉钉消息数据不完整。');
    }
    final type = DingTalkConversationType.values.firstWhere(
      (item) => item.name == '${json['conversation_type'] ?? ''}',
      orElse: () => DingTalkConversationType.direct,
    );
    final role = DingTalkGatewayMessageRole.values.firstWhere(
      (item) => item.name == '${json['role'] ?? ''}',
      orElse: () => DingTalkGatewayMessageRole.user,
    );
    DingTalkAutomaticReplyCard? automaticReplyCard;
    final storedAutomaticReplyCard = json['automatic_reply_card'];
    if (storedAutomaticReplyCard is Map) {
      try {
        automaticReplyCard = DingTalkAutomaticReplyCard.fromJson(
          stringKeyedMapFromValue(storedAutomaticReplyCard),
        );
      } on FormatException {
        automaticReplyCard = null;
      }
    }
    automaticReplyCard ??= parseDingTalkAutomaticReplyCard(rawContent);
    final storedMessageType = DingTalkGatewayMessageType.fromStorage(
      json['message_type'],
    );
    final messageType = automaticReplyCard == null
        ? storedMessageType
        : DingTalkGatewayMessageType.automaticReply;
    final rawEditHistory = json['edit_history'];
    final editHistory = rawEditHistory is List
        ? rawEditHistory
              .take(32)
              .whereType<Map>()
              .map((item) {
                try {
                  return DingTalkMessageEditRecord.fromJson(
                    stringKeyedMapFromValue(item),
                  );
                } catch (_) {
                  return null;
                }
              })
              .whereType<DingTalkMessageEditRecord>()
              .toList(growable: false)
        : const <DingTalkMessageEditRecord>[];
    final projection = parseDingTalkDwsFileProjection(rawContent);
    final storedMedia = _dingTalkGatewayMediaList(json['media'])
        .where(
          (item) => !isDingTalkResourceIdInUrlQuery(
            rawContent,
            item.resourceId,
            resourceType: item.resourceType,
          ),
        )
        .toList(growable: false);
    final forwardedMessages = _dingTalkForwardedMessageList(
      json['forwarded_messages'],
    );
    final quotedMessage = _dingTalkQuotedMessage(
      json['quoted_message'] ?? json['quotedMessage'],
    );
    final media = <DingTalkGatewayMedia>[
      if (storedMedia.isNotEmpty)
        ...storedMedia
      else if (projection != null)
        DingTalkGatewayMedia(
          resourceId: projection.resourceId,
          messageId: id,
          conversationId: conversationId,
          resourceType: DingTalkMediaResourceType.fileId,
          kind: DingTalkMediaKindX.fromFileName(projection.name),
          name: projection.name,
        ),
    ];
    final seenMedia = media
        .map((item) => '${item.resourceType.name}:${item.resourceId}')
        .toSet();
    for (final item in forwardedMessages.expand((value) => value.media)) {
      if (media.length >= 12 ||
          !seenMedia.add('${item.resourceType.name}:${item.resourceId}')) {
        continue;
      }
      media.add(
        item.conversationId.trim().isEmpty
            ? item.copyWith(conversationId: conversationId)
            : item,
      );
    }
    final storedForwardedCount = int.tryParse(
      '${json['forwarded_message_count'] ?? ''}',
    );
    final automaticReplyText = automaticReplyCard?.plainText ?? '';
    final textContent = automaticReplyCard == null
        ? normalizeDingTalkMediaText(rawContent, media)
        : automaticReplyText.isNotEmpty
        ? automaticReplyText
        : automaticReplyCard.title;
    final content = textContent.isEmpty && media.isNotEmpty
        ? media.map((item) => '[${item.displayName}]').join(' ')
        : textContent;
    return DingTalkGatewayMessage(
      id: id,
      conversationId: conversationId,
      conversationType: type,
      role: role,
      content: content,
      createdAt: createdAt,
      senderName: '${json['sender_name'] ?? ''}',
      senderId: '${json['sender_id'] ?? ''}',
      conversationTitle: '${json['conversation_title'] ?? ''}',
      messageType: messageType,
      automaticReplyCard: automaticReplyCard,
      media: media,
      quotedMessage: quotedMessage,
      forwardedMessages: forwardedMessages,
      forwardedMessageCount:
          storedForwardedCount != null &&
              storedForwardedCount >= forwardedMessages.length
          ? storedForwardedCount
          : forwardedMessages.length,
      fromSelf: boolFromValue(json['from_self']),
      failed: boolFromValue(json['failed']),
      mentionedCurrentUser: boolFromValue(json['mentioned_current_user']),
      readByPeer: boolFromValue(
        json['read_by_peer'] ?? json['is_read'] ?? json['read'],
      ),
      aiResponseState: DingTalkMessageAiResponseState.fromStorage(
        json['ai_response_state'],
      ),
      recalled: boolFromValue(
        json['recalled'] ?? json['is_recalled'] ?? json['recall'],
      ),
      ignoredForAiContext: boolFromValue(json['ignored_for_ai_context']),
      reactions: parseDingTalkMessageReactions(json),
      editHistory: editHistory,
      sourceAiMessageId: '${json['source_ai_message_id'] ?? ''}'.trim(),
      responseEchoType: DingTalkResponseEchoType.fromStorage(
        json['response_echo_type'],
      ),
      feedback: DingTalkGatewayMessageFeedback.fromStorage(json['feedback']),
    );
  }

  final String id;
  final String conversationId;
  final DingTalkConversationType conversationType;
  final DingTalkGatewayMessageRole role;
  final String content;
  final DateTime createdAt;
  final String senderName;
  final String senderId;
  final String conversationTitle;
  final DingTalkGatewayMessageType messageType;
  final DingTalkAutomaticReplyCard? automaticReplyCard;
  final List<DingTalkGatewayMedia> media;
  final DingTalkQuotedMessage? quotedMessage;
  final List<DingTalkForwardedMessage> forwardedMessages;
  final int forwardedMessageCount;
  final bool fromSelf;
  final bool failed;
  final bool mentionedCurrentUser;
  final bool readByPeer;
  final DingTalkMessageAiResponseState aiResponseState;
  final bool recalled;
  final bool ignoredForAiContext;
  final List<String> reactions;
  // 仅表示当前对象来自完整查询结果，不写入持久化数据。
  final bool reactionSnapshotComplete;
  final List<DingTalkMessageEditRecord> editHistory;
  final String sourceAiMessageId;
  final DingTalkResponseEchoType? responseEchoType;
  final DingTalkGatewayMessageFeedback? feedback;

  bool get isAssistant => role == DingTalkGatewayMessageRole.assistant;
  bool get isAutomaticReply =>
      messageType == DingTalkGatewayMessageType.automaticReply &&
      automaticReplyCard != null;
  bool get hasQuotedMessage => quotedMessage != null;
  bool get isForwardedChatRecord => forwardedMessages.isNotEmpty;
  Iterable<DingTalkGatewayMedia> get contextualMedia sync* {
    yield* media;
    final quoted = quotedMessage;
    if (quoted != null) yield* quoted.media;
  }

  bool get isEdited => editHistory.isNotEmpty;
  bool get isContentHidden => recalled || ignoredForAiContext;
  bool get isExcludedFromAiContext => isContentHidden || isAutomaticReply;
  bool get isThinkingEcho =>
      responseEchoType == DingTalkResponseEchoType.thinking;
  bool get isToolCallEcho =>
      responseEchoType == DingTalkResponseEchoType.toolCall ||
      (responseEchoType == null &&
          isAssistant &&
          sourceAiMessageId.isNotEmpty &&
          content.trimLeft().startsWith('### 工具调用'));

  DingTalkGatewayMessage copyWith({
    String? id,
    String? content,
    DingTalkGatewayMessageType? messageType,
    DingTalkAutomaticReplyCard? automaticReplyCard,
    List<DingTalkGatewayMedia>? media,
    DingTalkQuotedMessage? quotedMessage,
    List<DingTalkForwardedMessage>? forwardedMessages,
    int? forwardedMessageCount,
    bool? fromSelf,
    bool? mentionedCurrentUser,
    bool? readByPeer,
    DingTalkMessageAiResponseState? aiResponseState,
    bool? recalled,
    bool? ignoredForAiContext,
    List<String>? reactions,
    bool? reactionSnapshotComplete,
    List<DingTalkMessageEditRecord>? editHistory,
    String? sourceAiMessageId,
    DingTalkResponseEchoType? responseEchoType,
    DingTalkGatewayMessageFeedback? feedback,
    bool clearFeedback = false,
  }) {
    return DingTalkGatewayMessage(
      id: id ?? this.id,
      conversationId: conversationId,
      conversationType: conversationType,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      senderName: senderName,
      senderId: senderId,
      conversationTitle: conversationTitle,
      messageType: messageType ?? this.messageType,
      automaticReplyCard: automaticReplyCard ?? this.automaticReplyCard,
      media: media ?? this.media,
      quotedMessage: quotedMessage ?? this.quotedMessage,
      forwardedMessages: forwardedMessages ?? this.forwardedMessages,
      forwardedMessageCount:
          forwardedMessageCount ?? this.forwardedMessageCount,
      fromSelf: fromSelf ?? this.fromSelf,
      failed: failed,
      mentionedCurrentUser: mentionedCurrentUser ?? this.mentionedCurrentUser,
      readByPeer: readByPeer ?? this.readByPeer,
      aiResponseState: aiResponseState ?? this.aiResponseState,
      recalled: recalled ?? this.recalled,
      ignoredForAiContext: ignoredForAiContext ?? this.ignoredForAiContext,
      reactions: reactions ?? this.reactions,
      reactionSnapshotComplete:
          reactionSnapshotComplete ?? this.reactionSnapshotComplete,
      editHistory: editHistory ?? this.editHistory,
      sourceAiMessageId: sourceAiMessageId ?? this.sourceAiMessageId,
      responseEchoType: responseEchoType ?? this.responseEchoType,
      feedback: clearFeedback ? null : feedback ?? this.feedback,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'conversation_id': conversationId,
    'conversation_type': conversationType.name,
    'role': role.name,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'sender_name': senderName,
    'sender_id': senderId,
    'conversation_title': conversationTitle,
    'message_type': messageType.storageValue,
    'automatic_reply_card': automaticReplyCard?.toJson(),
    'media': media.map((item) => item.toJson()).toList(growable: false),
    'quoted_message': quotedMessage?.toJson(),
    'forwarded_messages': forwardedMessages
        .map((item) => item.toJson())
        .toList(growable: false),
    'forwarded_message_count': forwardedMessageCount,
    'from_self': fromSelf,
    'failed': failed,
    'mentioned_current_user': mentionedCurrentUser,
    'read_by_peer': readByPeer,
    'ai_response_state': aiResponseState.storageValue,
    'recalled': recalled,
    'ignored_for_ai_context': ignoredForAiContext,
    'reactions': reactions,
    'edit_history': editHistory
        .map((item) => item.toJson())
        .toList(growable: false),
    'source_ai_message_id': sourceAiMessageId,
    'response_echo_type': responseEchoType?.storageValue,
    'feedback': feedback?.storageValue,
  };
}

class DingTalkConversation {
  DingTalkConversation({
    required this.id,
    required this.type,
    required this.title,
    List<DingTalkGatewayMessage> messages = const <DingTalkGatewayMessage>[],
    DateTime? createdAt,
    this.openConversationId,
    this.directUserId,
    this.directOpenDingTalkId,
  }) : createdAt = createdAt ?? DateTime.now(),
       messages = List<DingTalkGatewayMessage>.from(messages);

  factory DingTalkConversation.fromJson(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final title = '${json['title'] ?? ''}'.trim();
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException('钉钉会话数据不完整。');
    }
    final type = DingTalkConversationType.values.firstWhere(
      (item) => item.name == '${json['type'] ?? ''}',
      orElse: () => DingTalkConversationType.direct,
    );
    final rawMessages = json['messages'];
    final messages = rawMessages is List
        ? rawMessages
              .whereType<Map>()
              .map((item) {
                try {
                  return DingTalkGatewayMessage.fromJson(
                    stringKeyedMapFromValue(item),
                  );
                } catch (_) {
                  return null;
                }
              })
              .whereType<DingTalkGatewayMessage>()
              .toList(growable: false)
        : const <DingTalkGatewayMessage>[];
    final conversation = DingTalkConversation(
      id: id,
      type: type,
      title: title,
      messages: messages,
      createdAt:
          DateTime.tryParse('${json['created_at'] ?? ''}') ??
          (messages.isEmpty ? DateTime.now() : messages.first.createdAt),
      openConversationId: nullIfBlank(
        '${json['open_conversation_id'] ?? json['openConversationId'] ?? ''}',
      ),
      directUserId: nullIfBlank('${json['direct_user_id'] ?? ''}'),
      directOpenDingTalkId: nullIfBlank(
        '${json['direct_open_dingtalk_id'] ?? ''}',
      ),
    );
    final sessionId = '${json['ai_session_id'] ?? ''}'.trim();
    conversation.aiSessionId = sessionId.isEmpty ? null : sessionId;
    final checkpointId = '${json['ai_context_checkpoint_message_id'] ?? ''}'
        .trim();
    conversation.aiContextCheckpointMessageId = checkpointId.isEmpty
        ? null
        : checkpointId;
    return conversation;
  }

  final String id;
  final DingTalkConversationType type;
  String title;
  final List<DingTalkGatewayMessage> messages;
  final DateTime createdAt;

  /// DWS 编辑消息所需的 openConversationId。直聊在首次收到事件后补齐。
  String? openConversationId;
  String? aiSessionId;
  String? aiContextCheckpointMessageId;
  String? directUserId;
  String? directOpenDingTalkId;

  String get dwsConversationId {
    final remoteId = openConversationId?.trim() ?? '';
    if (remoteId.isNotEmpty) return remoteId;
    return type == DingTalkConversationType.group ? id : '';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type.name,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'open_conversation_id': openConversationId,
    'ai_session_id': aiSessionId,
    'ai_context_checkpoint_message_id': aiContextCheckpointMessageId,
    'direct_user_id': directUserId,
    'direct_open_dingtalk_id': directOpenDingTalkId,
    'messages': messages.map((item) => item.toJson()).toList(growable: false),
  };

  DateTime get updatedAt =>
      messages.isEmpty ? createdAt : messages.last.createdAt;

  String get preview => messages.isEmpty ? '' : messages.last.content;
}

@immutable
class DingTalkAuthStatus {
  const DingTalkAuthStatus({
    required this.authenticated,
    this.identity = const DingTalkIdentity(),
  });

  final bool authenticated;
  final DingTalkIdentity identity;
}
