import 'dart:math' as math;

import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';

const Set<String> _webQualityStopWords = <String>{
  'the',
  'a',
  'an',
  'is',
  'are',
  'was',
  'were',
  'be',
  'been',
  'being',
  'have',
  'has',
  'had',
  'do',
  'does',
  'did',
  'will',
  'would',
  'shall',
  'should',
  'may',
  'might',
  'must',
  'can',
  'could',
  'to',
  'of',
  'in',
  'for',
  'on',
  'with',
  'at',
  'by',
  'from',
  'as',
  'into',
  'through',
  'during',
  'before',
  'after',
  'above',
  'below',
  'between',
  'and',
  'but',
  'or',
  'not',
  'no',
  'nor',
  'so',
  'yet',
  'both',
  'either',
  'neither',
  'each',
  'every',
  'all',
  'any',
  'few',
  'more',
  'most',
  'other',
  'some',
  'such',
  'than',
  'too',
  'very',
  'just',
  'about',
  'also',
  'then',
  'this',
  'that',
  'these',
  'those',
  'it',
  'its',
  'i',
  'we',
  'you',
  'they',
  'he',
  'she',
  'me',
  'us',
  'him',
  'her',
  'them',
  'my',
  'our',
  'your',
  'their',
  'what',
  'which',
  'who',
  'whom',
  'when',
  'where',
  'why',
  'how',
  'if',
  'up',
  'out',
  'off',
  'over',
  'under',
  'again',
  '的',
  '了',
  '在',
  '是',
  '我',
  '有',
  '和',
  '就',
  '不',
  '人',
  '都',
  '一',
  '个',
  '上',
  '也',
  '很',
  '到',
  '说',
  '要',
  '去',
  '你',
  '会',
  '着',
  '没有',
  '看',
  '好',
  '自己',
  '这',
  '他',
  '她',
  '它',
  '们',
  '吗',
  '吧',
  '被',
  '让',
  '给',
  '把',
  '那',
  '些',
  '么',
  '什么',
  '怎么',
  '哪',
  '谁',
};

final RegExp _webQualitySplitPattern = RegExp(r'[^\w\u4e00-\u9fff]+');
final RegExp _webQualityWhitespacePattern = RegExp(r'\s+');
final RegExp _webQualityLineBreakPattern = RegExp(r'\r?\n');
final RegExp _webQualityAlphaNumericPattern = RegExp(
  r'[A-Za-z0-9\u4e00-\u9fff]',
);

List<String> webQualityTerms(
  String input, {
  int limit = 24,
  bool preserveCase = false,
}) {
  if (limit <= 0) return const <String>[];
  final seen = <String>{};
  final terms = <String>[];
  for (final part
      in input
          .replaceAll(_webQualitySplitPattern, ' ')
          .split(_webQualityWhitespacePattern)) {
    final normalized = lowercaseStringFromValue(part);
    if (normalized.length < 2 || _webQualityStopWords.contains(normalized)) {
      continue;
    }
    if (seen.add(normalized)) {
      terms.add(preserveCase ? part : normalized);
      if (terms.length >= limit) break;
    }
  }
  return terms;
}

List<String> _webQualityAllTerms(String input, {int limit = 240}) {
  final terms = <String>[];
  for (final part
      in input
          .replaceAll(_webQualitySplitPattern, ' ')
          .split(_webQualityWhitespacePattern)) {
    final term = lowercaseStringFromValue(part);
    if (term.length < 2 || _webQualityStopWords.contains(term)) continue;
    terms.add(term);
    if (terms.length >= limit) break;
  }
  return terms;
}

double webTextRelevanceScore(String query, String text) {
  final terms = webQualityTerms(query);
  if (terms.isEmpty) return 0;
  final lowerText = text.toLowerCase();
  var matches = 0;
  for (final term in terms) {
    if (lowerText.contains(term)) matches += 1;
  }
  return matches / terms.length;
}

bool webHasInformativeSearchText({
  required String title,
  required String url,
  required String snippet,
  String? rawContent,
}) {
  final normalizedTitle = lowercaseStringFromValue(title);
  final normalizedUrl = lowercaseStringFromValue(url);
  final body = '${snippet.trim()} ${(rawContent ?? '').trim()}'.trim();
  if (body.length >= 8) return true;
  if (normalizedTitle.isEmpty || normalizedTitle == normalizedUrl) {
    return false;
  }
  return normalizedTitle.length >= 4;
}

String webPromptExcerpt(String input, int maxChars) {
  if (maxChars <= 0) return '';
  final seenLines = <String>{};
  final lines = <String>[];
  for (final line in _webQualityNormalizedLines(input, minLength: 2)) {
    if (seenLines.add(line.toLowerCase())) lines.add(line);
  }
  final cleaned = lines.isEmpty
      ? input.trim().replaceAll(_webQualityWhitespacePattern, ' ')
      : lines.join('\n');
  return clipTextByCodeUnits(cleaned, maxChars, suffix: '…');
}

double webContentQualityScore(String content) {
  final sample = content.trim();
  if (sample.isEmpty) return -400;
  final capped = clipTextByCodeUnits(sample, 20000, suffix: '');
  var score = 0.0;

  if (capped.length < 200) {
    score -= (200 - capped.length).clamp(0, 160) * 0.5;
  }

  final lines = _webQualityNormalizedLines(capped, minLength: 3);
  if (lines.length >= 6) {
    final uniqueLineRatio = lines.toSet().length / lines.length;
    score -= (1 - uniqueLineRatio) * 160;
  }

  final terms = _webQualityAllTerms(capped);
  if (terms.length >= 20) {
    final uniqueTermRatio = terms.toSet().length / terms.length;
    if (uniqueTermRatio < 0.35) {
      score -= (0.35 - uniqueTermRatio) * 300;
    }
  }

  final alphaNumericCount = _webQualityAlphaNumericPattern
      .allMatches(capped)
      .length;
  final alphaNumericRatio = alphaNumericCount / math.max(capped.length, 1);
  if (alphaNumericRatio < 0.25) {
    score -= 100;
  } else if (alphaNumericRatio < 0.45) {
    score -= 50;
  }

  final lower = capped.toLowerCase();
  var boilerplateHits = 0;
  for (final phrase in const <String>[
    'accept cookies',
    'cookie policy',
    'privacy policy',
    'subscribe to',
    'sign in',
    'enable javascript',
    'all rights reserved',
    '继续浏览',
    '隐私政策',
    '登录',
    '订阅',
    'cookie',
  ]) {
    if (lower.contains(phrase)) boilerplateHits += 1;
  }
  score -= math.min(boilerplateHits, 4) * 35;

  return score;
}

List<String> _webQualityNormalizedLines(
  String input, {
  required int minLength,
}) {
  return input
      .trim()
      .split(_webQualityLineBreakPattern)
      .map(collapseInlineWhitespace)
      .where((line) => line.length >= minLength)
      .toList(growable: false);
}
