import 'dart:convert';
import 'dart:ui' show Locale;

import 'localized_text.dart';

/// 两端共用的持久化消息格式；历史记录、复制和导出均保留原始决策数据。
abstract final class DecisionPayload {
  static const requestLanguage = 'openhand-decision-request';
  static const resultLanguage = 'openhand-decision';
  static final _resultFence = RegExp(
    r'^ {0,3}(?:`{3,}|~{3,})openhand-decision[ \t]*\r?$',
    multiLine: true,
  );
  static final _requestFence = RegExp(
    r'^ {0,3}(`{3,}|~{3,})openhand-decision-request[ \t]*\r?$',
    multiLine: true,
  );

  static bool containsRequest(String content) =>
      content.contains(requestLanguage) && _requestFence.hasMatch(content);

  static bool containsResult(String content) =>
      content.contains(resultLanguage) && _resultFence.hasMatch(content);
  static const typeNoul = 'noul';
  static const typeChoice = 'choice';
  static const typeScore = 'score';
  static const types = {typeNoul, typeChoice, typeScore};
  static const simpleQuestionKey = '决策';
  static const fallbackQuestionKey = '判断';
  static const modelFallback = 'Jev';
  static const maxCharacters = 1024 * 1024;
  static const maxQuestions = 128;
  static const maxCriteria = 255;
  static const minScoreLevels = 2;
  static const maxScoreLevels = 10;
  static const percentFractionDigits = 1;

  static const questionNoulZh = '根据所给信息，这段陈述是否成立？';
  static const questionNoulZhHant = '根據所給資訊，這段陳述是否成立？';
  static const questionNoulEn =
      'Based on the given information, is this statement true?';
  static const questionNoulFr =
      'D’après les informations fournies, cette affirmation est-elle vraie ?';
  static const questionNoulDe =
      'Ist diese Aussage anhand der gegebenen Informationen zutreffend?';
  static const questionNoulJa = '提示された情報に基づき、この記述は成り立ちますか？';

  static const questionChoiceZh = '根据所给信息，哪个候选项最符合？';
  static const questionChoiceZhHant = '根據所給資訊，哪個候選項最符合？';
  static const questionChoiceEn =
      'Based on the given information, which option fits best?';
  static const questionChoiceFr =
      'D’après les informations fournies, quelle option convient le mieux ?';
  static const questionChoiceDe =
      'Welche Option passt anhand der gegebenen Informationen am besten?';
  static const questionChoiceJa = '提示された情報に基づき、どの候補が最も適切ですか？';

  static const questionScoreZh = '依据从低到高排列的等级，对所给内容评分。';
  static const questionScoreZhHant = '依據從低到高排列的等級，對所給內容評分。';
  static const questionScoreEn =
      'Score the given content using the levels ordered from low to high.';
  static const questionScoreFr =
      'Notez le contenu selon les niveaux, du plus bas au plus haut.';
  static const questionScoreDe =
      'Bewerten Sie den Inhalt anhand der Stufen von niedrig nach hoch.';
  static const questionScoreJa = '低い順に並べた等級で、提示された内容を評価してください。';

  static const defaultQuestion = questionNoulZh;
  static const defaultQuestions = {
    typeNoul: questionNoulZh,
    typeChoice: questionChoiceZh,
    typeScore: questionScoreZh,
  };

  static const builtInQuestionTexts = {
    questionNoulZh,
    questionNoulZhHant,
    questionNoulEn,
    questionNoulFr,
    questionNoulDe,
    questionNoulJa,
    questionChoiceZh,
    questionChoiceZhHant,
    questionChoiceEn,
    questionChoiceFr,
    questionChoiceDe,
    questionChoiceJa,
    questionScoreZh,
    questionScoreZhHant,
    questionScoreEn,
    questionScoreFr,
    questionScoreDe,
    questionScoreJa,
  };

  static bool isBuiltInQuestion(String text) =>
      builtInQuestionTexts.contains(text.trim());

  static String defaultQuestionForType(String type, [Locale? locale]) {
    final resolved = openHandSupportedUiLocale(locale ?? openHandAmbientLocale);
    final hant = resolved.scriptCode?.toLowerCase() == 'hant';
    switch (resolved.languageCode) {
      case 'zh':
        return switch (type) {
          typeChoice => hant ? questionChoiceZhHant : questionChoiceZh,
          typeScore => hant ? questionScoreZhHant : questionScoreZh,
          _ => hant ? questionNoulZhHant : questionNoulZh,
        };
      case 'fr':
        return switch (type) {
          typeChoice => questionChoiceFr,
          typeScore => questionScoreFr,
          _ => questionNoulFr,
        };
      case 'de':
        return switch (type) {
          typeChoice => questionChoiceDe,
          typeScore => questionScoreDe,
          _ => questionNoulDe,
        };
      case 'ja':
        return switch (type) {
          typeChoice => questionChoiceJa,
          typeScore => questionScoreJa,
          _ => questionNoulJa,
        };
      default:
        return switch (type) {
          typeChoice => questionChoiceEn,
          typeScore => questionScoreEn,
          _ => questionNoulEn,
        };
    }
  }

  /// 仅替换空问题或内置默认文案，保留用户自定义问题。
  static String questionForType(
    String type, {
    String current = '',
    String? localizedDefault,
  }) {
    final fallback =
        (localizedDefault != null && localizedDefault.trim().isNotEmpty)
        ? localizedDefault
        : defaultQuestionForType(type);
    final text = current.trim();
    return text.isEmpty || isBuiltInQuestion(text) ? fallback : current;
  }

  static String encode(String language, Map<String, Object?> data) =>
      '```$language\n${jsonEncode(data).replaceAll('`', r'\u0060')}\n```';

  static String percentLabel(num value) =>
      '${(unit(value) * 100).toStringAsFixed(percentFractionDigits)}%';

  static double unit(num value) {
    if (!value.isFinite) return 0;
    if (value <= 0) return 0;
    if (value >= 1) return 1;
    return value.toDouble();
  }

  static String displayText(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } on JsonUnsupportedObjectError {
      return value.toString();
    }
  }

  static Map<String, Object?>? tryRequest(String text) {
    try {
      return request(text);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static Map<String, Object?>? tryResult(String text) {
    if (text.length > maxCharacters) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final questions = decoded['questions'];
      if (questions is! Map ||
          questions.isEmpty ||
          questions.length > maxQuestions) {
        return null;
      }
      return result(
        Map<String, Object?>.from(decoded),
        Map<String, Object?>.from(questions),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// 草稿允许尚未填写的字段；发送请求默认执行完整校验。
  static Map<String, Object?> request(
    String text, {
    bool allowIncomplete = false,
  }) {
    if (text.length > maxCharacters) {
      throw FormatException(_tooLong);
    }
    final opening = _requestFence.firstMatch(text);
    Object? decoded;
    if (opening != null) {
      final fence = opening[1]!;
      final closing = RegExp(
        '^ {0,3}${fence[0]}{${fence.length},}'
        r'[ \t]*\r?$',
        multiLine: true,
      ).firstMatch(text.substring(opening.end));
      if (closing == null) throw FormatException(_incomplete);
      decoded = jsonDecode(
        text.substring(opening.end, opening.end + closing.start),
      );
    } else if (text.trimLeft().startsWith('{')) {
      decoded = jsonDecode(text);
    } else {
      decoded = <String, Object?>{
        'state': text.trim(),
        'questions': {
          fallbackQuestionKey: {
            'type': typeNoul,
            'instructions': defaultQuestionForType(typeNoul),
          },
        },
      };
    }
    if (decoded is! Map || !decoded.containsKey('state')) {
      throw FormatException(_needStateQuestions);
    }
    final state = decoded['state'];
    if (state is! String && state is! Map && state is! List ||
        state is String && state.trim().isEmpty && !allowIncomplete) {
      throw FormatException(_emptyState);
    }
    final questions = decoded['questions'];
    if (questions is! Map ||
        questions.isEmpty ||
        questions.length > maxQuestions) {
      throw FormatException(_questionCount);
    }
    for (final entry in questions.entries) {
      final question = entry.value;
      if (entry.key is! String ||
          (entry.key as String).trim().isEmpty ||
          question is! Map) {
        throw FormatException(_needName);
      }
      final instructions = question['instructions'];
      if (instructions is! String &&
              instructions is! Map &&
              instructions is! List ||
          instructions is String &&
              instructions.trim().isEmpty &&
              !allowIncomplete) {
        throw FormatException(_needInstructions);
      }
      final criteria = question['criteria'];
      switch (question['type']) {
        case typeChoice:
          if (criteria is! Map ||
              (!allowIncomplete && criteria.isEmpty) ||
              criteria.length > maxCriteria) {
            throw FormatException(_choiceCount);
          }
        case typeScore:
          if (criteria is! List ||
              (!allowIncomplete && criteria.length < minScoreLevels) ||
              criteria.length > maxScoreLevels) {
            throw FormatException(_scoreCount);
          }
        case typeNoul:
          if (criteria != null && criteria is! Map) {
            throw FormatException(_noulCriteria);
          }
        default:
          throw FormatException(_badType);
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
      throw FormatException(_noAnswers);
    }
    if (answers.length != questions.length) {
      throw FormatException(_answerMismatch);
    }
    for (final entry in questions.entries) {
      final answer = answers[entry.key];
      final question = entry.value as Map;
      if (answer is! Map || answer['type'] != question['type']) {
        throw FormatException(_answerMismatch);
      }
      final type = answer['type'];
      if (!types.contains(type)) {
        throw FormatException(_badAnswerType);
      }
      if (type == typeNoul && !probability(answer['noul'])) {
        throw FormatException(_badNoul);
      }
      if (type == typeChoice &&
          (answer['choice'] is! String ||
              !(question['criteria'] as Map).containsKey(answer['choice']))) {
        throw FormatException(_badChoice);
      }
      if (type == typeScore &&
          (answer['score'] is! num || !(answer['score'] as num).isFinite)) {
        throw FormatException(_badScore);
      }
      if (answer.containsKey('confidence') &&
          !probability(answer['confidence'])) {
        throw FormatException(_badConfidence);
      }
      if (type != typeNoul) {
        final probabilities = answer['probabilities'];
        if (probabilities is! Map ||
            probabilities.isEmpty ||
            probabilities.length > maxCriteria ||
            !probabilities.values.every(probability)) {
          throw FormatException(_badDistribution);
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

  static String get _tooLong => openHandAmbientText(
    zh: '决策内容过长，请缩小输入范围。',
    zhHant: '決策內容過長，請縮小輸入範圍。',
    en: 'Decision content is too long. Narrow the input.',
    fr: 'Le contenu de décision est trop long. Réduisez la saisie.',
    de: 'Der Entscheidungsinhalt ist zu lang. Eingabe eingrenzen.',
    ja: '意思決定の内容が長すぎます。入力範囲を狭めてください。',
  );

  static String get _incomplete => openHandAmbientText(
    zh: '决策配置尚未完整，请重新打开决策配置。',
    zhHant: '決策設定尚未完整，請重新開啟決策設定。',
    en: 'The decision draft is incomplete. Open the decision editor again.',
    fr: 'Le brouillon de décision est incomplet. Rouvrez l’éditeur.',
    de: 'Der Entscheidungsentwurf ist unvollständig. Editor erneut öffnen.',
    ja: '意思決定の下書きが不完全です。設定を開き直してください。',
  );

  static String get _needStateQuestions => openHandAmbientText(
    zh: '决策配置需要待评估内容和问题。',
    zhHant: '決策設定需要待評估內容和問題。',
    en: 'A decision draft needs content to evaluate and at least one question.',
    fr: 'Un brouillon de décision nécessite un contenu et une question.',
    de: 'Ein Entscheidungsentwurf braucht Inhalt und mindestens eine Frage.',
    ja: '意思決定の下書きには評価対象と質問が必要です。',
  );

  static String get _emptyState => openHandAmbientText(
    zh: '待评估内容不能为空，且须为文本、对象或数组。',
    zhHant: '待評估內容不能為空，且須為文字、物件或陣列。',
    en: 'Content to evaluate cannot be empty and must be text, an object, or an array.',
    fr: 'Le contenu à évaluer ne peut pas être vide ; texte, objet ou tableau uniquement.',
    de: 'Der Bewertungsinhalt darf nicht leer sein und muss Text, Objekt oder Array sein.',
    ja: '評価対象は空にできず、テキスト・オブジェクト・配列のいずれかである必要があります。',
  );

  static String get _questionCount => openHandAmbientText(
    zh: '请配置 1 至 128 个决策问题。',
    zhHant: '請設定 1 至 128 個決策問題。',
    en: 'Configure between 1 and 128 decision questions.',
    fr: 'Configurez entre 1 et 128 questions de décision.',
    de: 'Konfigurieren Sie 1 bis 128 Entscheidungsfragen.',
    ja: '意思決定の質問は 1〜128 件で設定してください。',
  );

  static String get _needName => openHandAmbientText(
    zh: '决策问题必须有唯一名称和完整配置。',
    zhHant: '決策問題必須有唯一名稱和完整設定。',
    en: 'Each decision question needs a unique name and a complete configuration.',
    fr: 'Chaque question de décision doit avoir un nom unique et une configuration complète.',
    de: 'Jede Entscheidungsfrage braucht einen eindeutigen Namen und eine vollständige Konfiguration.',
    ja: '各意思決定の質問には一意の名前と完全な設定が必要です。',
  );

  static String get _needInstructions => openHandAmbientText(
    zh: '请填写决策问题。',
    zhHant: '請填寫決策問題。',
    en: 'Enter the decision question.',
    fr: 'Saisissez la question de décision.',
    de: 'Geben Sie die Entscheidungsfrage ein.',
    ja: '意思決定の質問を入力してください。',
  );

  static String get _choiceCount => openHandAmbientText(
    zh: '选择题需要 1 至 255 个候选项。',
    zhHant: '選擇題需要 1 至 255 個候選項。',
    en: 'A choice question needs 1 to 255 options.',
    fr: 'Une question à choix nécessite 1 à 255 options.',
    de: 'Eine Auswahlfrage braucht 1 bis 255 Optionen.',
    ja: '選択式の質問には 1〜255 個の候補が必要です。',
  );

  static String get _scoreCount => openHandAmbientText(
    zh: '评分需要 2 至 10 个从低到高排列的等级。',
    zhHant: '評分需要 2 至 10 個從低到高排列的等級。',
    en: 'A score question needs 2 to 10 levels ordered from low to high.',
    fr: 'Une question de note nécessite 2 à 10 niveaux, du plus bas au plus haut.',
    de: 'Eine Bewertungsfrage braucht 2 bis 10 Stufen von niedrig nach hoch.',
    ja: '評点の質問には低い順の等級が 2〜10 個必要です。',
  );

  static String get _noulCriteria => openHandAmbientText(
    zh: '判断标准必须是对象。',
    zhHant: '判斷標準必須是物件。',
    en: 'Judgement criteria must be an object.',
    fr: 'Les critères de jugement doivent être un objet.',
    de: 'Die Urteilskriterien müssen ein Objekt sein.',
    ja: '判断基準はオブジェクトである必要があります。',
  );

  static String get _badType => openHandAmbientText(
    zh: '决策类型仅支持选择、评分和判断。',
    zhHant: '決策類型僅支援選擇、評分和判斷。',
    en: 'Decision type must be choice, score, or judgement.',
    fr: 'Le type de décision doit être choix, note ou jugement.',
    de: 'Der Entscheidungstyp muss Auswahl, Bewertung oder Urteil sein.',
    ja: '意思決定タイプは選択・評点・判断のみです。',
  );

  static String get _noAnswers => openHandAmbientText(
    zh: '决策接口未返回有效答案。',
    zhHant: '決策介面未返回有效答案。',
    en: 'The decision API did not return valid answers.',
    fr: 'L’API de décision n’a pas renvoyé de réponses valides.',
    de: 'Die Entscheidungs-API hat keine gültigen Antworten geliefert.',
    ja: '意思決定 API が有効な回答を返しませんでした。',
  );

  static String get _answerMismatch => openHandAmbientText(
    zh: '决策答案缺失或类型不匹配。',
    zhHant: '決策答案缺失或類型不匹配。',
    en: 'A decision answer is missing or does not match its question type.',
    fr: 'Une réponse de décision est absente ou ne correspond pas au type de question.',
    de: 'Eine Entscheidungsantwort fehlt oder passt nicht zum Fragetyp.',
    ja: '意思決定の回答が欠けているか、質問タイプと一致しません。',
  );

  static String get _badAnswerType => openHandAmbientText(
    zh: '决策答案类型无效。',
    zhHant: '決策答案類型無效。',
    en: 'The decision answer type is invalid.',
    fr: 'Le type de réponse de décision n’est pas valide.',
    de: 'Der Antworttyp der Entscheidung ist ungültig.',
    ja: '意思決定の回答タイプが無効です。',
  );

  static String get _badNoul => openHandAmbientText(
    zh: '判断概率无效。',
    zhHant: '判斷機率無效。',
    en: 'The judgement probability is invalid.',
    fr: 'La probabilité de jugement n’est pas valide.',
    de: 'Die Urteilswahrscheinlichkeit ist ungültig.',
    ja: '判断確率が無効です。',
  );

  static String get _badChoice => openHandAmbientText(
    zh: '返回的选项不在候选范围内。',
    zhHant: '返回的選項不在候選範圍內。',
    en: 'The returned option is not in the candidate list.',
    fr: 'L’option renvoyée n’est pas dans la liste des candidats.',
    de: 'Die zurückgegebene Option liegt nicht in der Kandidatenliste.',
    ja: '返された選択肢が候補に含まれていません。',
  );

  static String get _badScore => openHandAmbientText(
    zh: '返回的评分无效。',
    zhHant: '返回的評分無效。',
    en: 'The returned score is invalid.',
    fr: 'La note renvoyée n’est pas valide.',
    de: 'Die zurückgegebene Bewertung ist ungültig.',
    ja: '返された評点が無効です。',
  );

  static String get _badConfidence => openHandAmbientText(
    zh: '决策置信度无效。',
    zhHant: '決策置信度無效。',
    en: 'The decision confidence is invalid.',
    fr: 'La confiance de la décision n’est pas valide.',
    de: 'Die Entscheidungskonfidenz ist ungültig.',
    ja: '意思決定の信頼度が無効です。',
  );

  static String get _badDistribution => openHandAmbientText(
    zh: '决策概率分布无效。',
    zhHant: '決策機率分布無效。',
    en: 'The decision probability distribution is invalid.',
    fr: 'La distribution de probabilités n’est pas valide.',
    de: 'Die Wahrscheinlichkeitsverteilung ist ungültig.',
    ja: '意思決定の確率分布が無効です。',
  );
}
