import 'dart:convert';

/// 两端共用的持久化消息格式；历史记录、复制和导出均保留原始决策数据。
abstract final class DecisionPayload {
  static const requestLanguage = 'openhand-decision-request';
  static const resultLanguage = 'openhand-decision';
  static const maxCharacters = 1024 * 1024;
  static const maxQuestions = 128;
  static const defaultQuestion = '根据所给信息，这段陈述是否成立？';
  static const defaultQuestions = {
    'noul': defaultQuestion,
    'choice': '根据所给信息，哪个候选项最符合？',
    'score': '依据从低到高排列的等级，对所给内容评分。',
  };

  /// 仅替换空问题或内置默认文案，保留用户自定义问题。
  static String questionForType(String type, {String current = ''}) {
    final text = current.trim();
    return text.isEmpty || defaultQuestions.containsValue(text)
        ? defaultQuestions[type]!
        : current;
  }

  static String encode(String language, Map<String, Object?> data) =>
      '```$language\n${jsonEncode(data).replaceAll('`', r'\u0060')}\n```';

  static Map<String, Object?> request(String text) {
    if (text.length > maxCharacters) {
      throw const FormatException('决策内容过长，请缩小输入范围。');
    }
    const marker = '```$requestLanguage\n';
    final start = text.indexOf(marker);
    Object? decoded;
    if (start >= 0) {
      final end = text.indexOf('```', start + marker.length);
      if (end < 0) throw const FormatException('决策配置尚未完整，请重新打开决策配置。');
      decoded = jsonDecode(text.substring(start + marker.length, end));
    } else if (text.trimLeft().startsWith('{')) {
      decoded = jsonDecode(text);
    } else {
      decoded = <String, Object?>{
        'state': text.trim(),
        'questions': {
          '判断': {'type': 'noul', 'instructions': defaultQuestion},
        },
      };
    }
    if (decoded is! Map || !decoded.containsKey('state')) {
      throw const FormatException('决策配置需要待评估内容和问题。');
    }
    final state = decoded['state'];
    if (state is! String && state is! Map && state is! List ||
        state is String && state.trim().isEmpty) {
      throw const FormatException('待评估内容不能为空，且须为文本、对象或数组。');
    }
    final questions = decoded['questions'];
    if (questions is! Map ||
        questions.isEmpty ||
        questions.length > maxQuestions) {
      throw const FormatException('请配置 1 至 128 个决策问题。');
    }
    for (final entry in questions.entries) {
      final question = entry.value;
      if (entry.key is! String ||
          (entry.key as String).trim().isEmpty ||
          question is! Map) {
        throw const FormatException('决策问题必须有唯一名称和完整配置。');
      }
      final instructions = question['instructions'];
      if (instructions is! String &&
              instructions is! Map &&
              instructions is! List ||
          instructions is String && instructions.trim().isEmpty) {
        throw const FormatException('请填写决策问题。');
      }
      final criteria = question['criteria'];
      switch (question['type']) {
        case 'choice':
          if (criteria is! Map || criteria.isEmpty || criteria.length > 255) {
            throw const FormatException('选择题需要 1 至 255 个候选项。');
          }
        case 'score':
          if (criteria is! List ||
              criteria.length < 2 ||
              criteria.length > 10) {
            throw const FormatException('评分需要 2 至 10 个从低到高排列的等级。');
          }
        case 'noul':
          if (criteria != null && criteria is! Map) {
            throw const FormatException('判断标准必须是对象。');
          }
        default:
          throw const FormatException('决策类型仅支持选择、评分和判断。');
      }
    }
    return {'state': state, 'questions': Map<String, Object?>.from(questions)};
  }

  static Map<String, Object?> result(
    Map<String, Object?> response,
    Map<String, Object?> questions,
  ) {
    final answers = response['answers'];
    if (answers is! Map || answers.isEmpty || answers.length > maxQuestions) {
      throw const FormatException('决策接口未返回有效答案。');
    }
    for (final entry in questions.entries) {
      final answer = answers[entry.key];
      final question = entry.value as Map;
      if (answer is! Map || answer['type'] != question['type']) {
        throw const FormatException('决策答案缺失或类型不匹配。');
      }
      final type = answer['type'];
      if (!const {'noul', 'choice', 'score'}.contains(type)) {
        throw const FormatException('决策答案类型无效。');
      }
      if (type == 'noul' && !probability(answer['noul'])) {
        throw const FormatException('判断概率无效。');
      }
      if (type == 'choice' &&
          (answer['choice'] is! String ||
              !(question['criteria'] as Map).containsKey(answer['choice']))) {
        throw const FormatException('返回的选项不在候选范围内。');
      }
      if (type == 'score' &&
          (answer['score'] is! num || !(answer['score'] as num).isFinite)) {
        throw const FormatException('返回的评分无效。');
      }
      if (answer.containsKey('confidence') &&
          !probability(answer['confidence'])) {
        throw const FormatException('决策置信度无效。');
      }
      if (type != 'noul') {
        final probabilities = answer['probabilities'];
        if (probabilities is! Map ||
            probabilities.isEmpty ||
            probabilities.length > 255 ||
            !probabilities.values.every(probability)) {
          throw const FormatException('决策概率分布无效。');
        }
      }
    }
    return {
      'model': response['model'],
      'answers': answers,
      'questions': questions,
    };
  }

  static bool probability(Object? value) =>
      value is num && value.isFinite && value >= 0 && value <= 1;
}
