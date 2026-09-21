import 'package:flutter/widgets.dart';

import '../util/decision_payload.dart';
import '../util/localized_text.dart';

/// Jev 决策卡片与表单共用的界面文案。
final class DecisionCopy {
  DecisionCopy._(this._t);

  factory DecisionCopy.of(BuildContext context) =>
      DecisionCopy._(openHandTextResolver(context));

  final OpenHandLocalizedTextResolver _t;

  String _m({
    required String zh,
    required String en,
    String? zhHant,
    String? fr,
    String? de,
    String? ja,
  }) => _t(zh: zh, en: en, zhHant: zhHant, fr: fr, de: de, ja: ja);

  String get requestTitle => _m(
    zh: '结构化决策',
    zhHant: '結構化決策',
    en: 'Structured decision',
    fr: 'Décision structurée',
    de: 'Strukturierte Entscheidung',
    ja: '構造化意思決定',
  );

  String get stateLabel => _m(
    zh: '待评估内容',
    zhHant: '待評估內容',
    en: 'Content to evaluate',
    fr: 'Contenu à évaluer',
    de: 'Zu bewertender Inhalt',
    ja: '評価対象',
  );

  String get questionLabel => _m(
    zh: '需要模型回答的问题',
    zhHant: '需要模型回答的問題',
    en: 'Question for the model',
    fr: 'Question pour le modèle',
    de: 'Frage an das Modell',
    ja: 'モデルに答えてほしい質問',
  );

  String get stateHint => _m(
    zh: '粘贴或输入需要评估的文本',
    zhHant: '貼上或輸入需要評估的文字',
    en: 'Paste or type the content to evaluate',
    fr: 'Collez ou saisissez le contenu à évaluer',
    de: 'Inhalt zum Bewerten einfügen oder eingeben',
    ja: '評価する内容を貼り付けるか入力',
  );

  String get questionHint => _m(
    zh: '一句话描述需要模型回答的问题',
    zhHant: '一句話描述需要模型回答的問題',
    en: 'Describe the question for the model',
    fr: 'Décrivez la question pour le modèle',
    de: 'Frage an das Modell beschreiben',
    ja: 'モデルに答えてほしい質問を書く',
  );

  String get questionsLabel => _m(
    zh: '决策问题',
    zhHant: '決策問題',
    en: 'Decision questions',
    fr: 'Questions de décision',
    de: 'Entscheidungsfragen',
    ja: '意思決定の質問',
  );

  String get typeGroupLabel => _m(
    zh: '决策类型',
    zhHant: '決策類型',
    en: 'Decision type',
    fr: 'Type de décision',
    de: 'Entscheidungstyp',
    ja: '意思決定タイプ',
  );

  String get choiceItemLabel => _m(
    zh: '候选项',
    zhHant: '候選項',
    en: 'Option',
    fr: 'Option',
    de: 'Option',
    ja: '候補',
  );

  String get scoreItemLabel => _m(
    zh: '评分等级（从低到高）',
    zhHant: '評分等級（從低到高）',
    en: 'Score level (low to high)',
    fr: 'Niveau de note (du plus bas au plus haut)',
    de: 'Bewertungsstufe (niedrig nach hoch)',
    ja: '評点等級（低い順）',
  );

  String get choiceHint => _m(
    zh: '例如：技术团队',
    zhHant: '例如：技術團隊',
    en: 'Example: Engineering',
    fr: 'Exemple : Ingénierie',
    de: 'Beispiel: Technik',
    ja: '例：技術チーム',
  );

  String get scoreHint => _m(
    zh: '例如：一般',
    zhHant: '例如：一般',
    en: 'Example: Medium',
    fr: 'Exemple : Moyen',
    de: 'Beispiel: Mittel',
    ja: '例：普通',
  );

  String get addChoice => _m(
    zh: '添加候选项',
    zhHant: '新增候選項',
    en: 'Add option',
    fr: 'Ajouter une option',
    de: 'Option hinzufügen',
    ja: '候補を追加',
  );

  String get addScore => _m(
    zh: '添加评分等级',
    zhHant: '新增評分等級',
    en: 'Add score level',
    fr: 'Ajouter un niveau',
    de: 'Stufe hinzufügen',
    ja: '評点等級を追加',
  );

  String get moveUp => _m(
    zh: '上移',
    zhHant: '上移',
    en: 'Move up',
    fr: 'Monter',
    de: 'Nach oben',
    ja: '上へ',
  );

  String get moveDown => _m(
    zh: '下移',
    zhHant: '下移',
    en: 'Move down',
    fr: 'Descendre',
    de: 'Nach unten',
    ja: '下へ',
  );

  String get typeNoul => _m(
    zh: '判断',
    zhHant: '判斷',
    en: 'Judgement',
    fr: 'Jugement',
    de: 'Urteil',
    ja: '判断',
  );

  String get typeChoice => _m(
    zh: '选择',
    zhHant: '選擇',
    en: 'Choice',
    fr: 'Choix',
    de: 'Auswahl',
    ja: '選択',
  );

  String get typeScore => _m(
    zh: '评分',
    zhHant: '評分',
    en: 'Score',
    fr: 'Note',
    de: 'Bewertung',
    ja: '評点',
  );

  String get held => _m(
    zh: '成立',
    zhHant: '成立',
    en: 'Holds',
    fr: 'Valide',
    de: 'Trifft zu',
    ja: '成立',
  );

  String get notHeld => _m(
    zh: '不成立',
    zhHant: '不成立',
    en: 'Does not hold',
    fr: 'Non valide',
    de: 'Trifft nicht zu',
    ja: '不成立',
  );

  String get confidence => _m(
    zh: '置信度',
    zhHant: '置信度',
    en: 'Confidence',
    fr: 'Confiance',
    de: 'Konfidenz',
    ja: '信頼度',
  );

  String get criteriaLabel => _m(
    zh: '判断标准',
    zhHant: '判斷標準',
    en: 'Criteria',
    fr: 'Critères',
    de: 'Kriterien',
    ja: '基準',
  );

  String get simpleQuestionName => _m(
    zh: '决策',
    zhHant: '決策',
    en: 'Decision',
    fr: 'Décision',
    de: 'Entscheidung',
    ja: '意思決定',
  );

  String typeLabel(String type) => switch (type) {
    DecisionPayload.typeChoice => typeChoice,
    DecisionPayload.typeScore => typeScore,
    _ => typeNoul,
  };

  String defaultQuestionFor(String type) => switch (type) {
    DecisionPayload.typeChoice => _m(
      zh: DecisionPayload.questionChoiceZh,
      zhHant: DecisionPayload.questionChoiceZhHant,
      en: DecisionPayload.questionChoiceEn,
      fr: DecisionPayload.questionChoiceFr,
      de: DecisionPayload.questionChoiceDe,
      ja: DecisionPayload.questionChoiceJa,
    ),
    DecisionPayload.typeScore => _m(
      zh: DecisionPayload.questionScoreZh,
      zhHant: DecisionPayload.questionScoreZhHant,
      en: DecisionPayload.questionScoreEn,
      fr: DecisionPayload.questionScoreFr,
      de: DecisionPayload.questionScoreDe,
      ja: DecisionPayload.questionScoreJa,
    ),
    _ => _m(
      zh: DecisionPayload.questionNoulZh,
      zhHant: DecisionPayload.questionNoulZhHant,
      en: DecisionPayload.questionNoulEn,
      fr: DecisionPayload.questionNoulFr,
      de: DecisionPayload.questionNoulDe,
      ja: DecisionPayload.questionNoulJa,
    ),
  };

  String questionName(String name) {
    final value = name.trim();
    final lower = value.toLowerCase();
    if (value == DecisionPayload.simpleQuestionKey || lower == 'decision') {
      return simpleQuestionName;
    }
    if (value == DecisionPayload.fallbackQuestionKey ||
        lower == DecisionPayload.typeNoul ||
        lower == 'judgement' ||
        lower == 'judgment') {
      return typeNoul;
    }
    if (lower == DecisionPayload.typeChoice) return typeChoice;
    if (lower == DecisionPayload.typeScore) return typeScore;
    return name;
  }

  String customQuestionName(String name, String type) {
    final value = name.trim();
    final lower = value.toLowerCase();
    if (value.isEmpty ||
        value == DecisionPayload.simpleQuestionKey ||
        lower == 'decision') {
      return '';
    }
    final named = questionName(name);
    return named == typeLabel(type) ? '' : named;
  }

  String localizedInstructions(String type, Object? raw) {
    if (raw is! String) return displayValue(raw);
    return DecisionPayload.questionForType(
      type,
      current: raw,
      localizedDefault: defaultQuestionFor(type),
    );
  }

  String confidenceLine(num value) =>
      '$confidence ${DecisionPayload.percentLabel(value)}';

  String displayValue(Object? value) {
    final text = DecisionPayload.displayText(value).trim();
    return text.isEmpty ? '—' : text;
  }
}
