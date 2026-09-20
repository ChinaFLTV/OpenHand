import 'package:flutter/widgets.dart';

import '../util/decision_payload.dart';
import '../util/localized_text.dart';

/// Jev 决策卡片、表单与弹窗共用的界面文案。
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

  String get resultTitle => _m(
    zh: '决策结果',
    zhHant: '決策結果',
    en: 'Decision result',
    fr: 'Résultat de décision',
    de: 'Entscheidungsergebnis',
    ja: '意思決定の結果',
  );

  String get resultSubtitle => _m(
    zh: '按问题查看答案与概率分布',
    zhHant: '按問題查看答案與機率分布',
    en: 'Inspect answers and probability by question',
    fr: 'Consultez les réponses et les probabilités par question',
    de: 'Antworten und Wahrscheinlichkeiten je Frage ansehen',
    ja: '質問ごとに回答と確率分布を確認',
  );

  String get requestTitle => _m(
    zh: '结构化决策',
    zhHant: '結構化決策',
    en: 'Structured decision',
    fr: 'Décision structurée',
    de: 'Strukturierte Entscheidung',
    ja: '構造化意思決定',
  );

  String get requestSubtitle => _m(
    zh: '待评估内容、问题与候选项已绑定到本次请求',
    zhHant: '待評估內容、問題與候選項已綁定到本次請求',
    en: 'Content, questions, and options are bound to this request',
    fr: 'Le contenu, les questions et les options sont liés à cette requête',
    de: 'Inhalt, Fragen und Optionen sind an diese Anfrage gebunden',
    ja: '評価対象・質問・候補がこのリクエストに紐づいています',
  );

  String get composerHint => _m(
    zh: '发送时调用决策接口',
    zhHant: '傳送時呼叫決策介面',
    en: 'The decision API runs when you send',
    fr: 'L’API de décision s’exécute à l’envoi',
    de: 'Die Entscheidungs-API läuft beim Senden',
    ja: '送信時に意思決定 API を呼び出します',
  );

  String get dialogTitle => _m(
    zh: '配置结构化决策',
    zhHant: '設定結構化決策',
    en: 'Configure structured decision',
    fr: 'Configurer une décision structurée',
    de: 'Strukturierte Entscheidung konfigurieren',
    ja: '構造化意思決定を設定',
  );

  String get dialogSubtitle => _m(
    zh: '定义问题、候选项与评分标准',
    zhHant: '定義問題、候選項與評分標準',
    en: 'Define questions, options, and scoring levels',
    fr: 'Définissez questions, options et niveaux de notation',
    de: 'Fragen, Optionen und Bewertungsstufen festlegen',
    ja: '質問・候補・評点基準を定義',
  );

  String get dialogBody => _m(
    zh: '先提供待评估内容，再定义要选择、评分或判断的问题。配置会写入草稿，点击发送后才调用模型。',
    zhHant: '先提供待評估內容，再定義要選擇、評分或判斷的問題。設定會寫入草稿，點選傳送後才呼叫模型。',
    en: 'Provide the content to evaluate, then define a choice, score, or judgement question. This only updates the draft; the model runs when you send.',
    fr: 'Fournissez le contenu à évaluer, puis définissez une question de choix, de note ou de jugement. Cela met seulement à jour le brouillon ; le modèle s’exécute à l’envoi.',
    de: 'Geben Sie den Bewertungsinhalt an und definieren Sie eine Auswahl-, Bewertungs- oder Urteilsfrage. Es wird nur der Entwurf aktualisiert; das Modell läuft beim Senden.',
    ja: '評価対象を入力し、選択・評点・判断の質問を定義します。下書きのみ更新され、送信時にモデルを呼び出します。',
  );

  String get applyToDraft => _m(
    zh: '应用到草稿',
    zhHant: '套用到草稿',
    en: 'Apply to draft',
    fr: 'Appliquer au brouillon',
    de: 'Auf Entwurf anwenden',
    ja: '下書きに適用',
  );

  String get invalidDraft => _m(
    zh: '现有决策草稿格式不完整，请修正配置。',
    zhHant: '現有決策草稿格式不完整，請修正設定。',
    en: 'The current decision draft is incomplete. Fix the configuration.',
    fr: 'Le brouillon de décision actuel est incomplet. Corrigez la configuration.',
    de: 'Der aktuelle Entscheidungsentwurf ist unvollständig. Konfiguration korrigieren.',
    ja: '現在の意思決定下書きが不完全です。設定を修正してください。',
  );

  String get checkConfig => _m(
    zh: '请检查决策配置。',
    zhHant: '請檢查決策設定。',
    en: 'Check the decision configuration.',
    fr: 'Vérifiez la configuration de décision.',
    de: 'Prüfen Sie die Entscheidungskonfiguration.',
    ja: '意思決定の設定を確認してください。',
  );

  String get duplicateOptions => _m(
    zh: '候选项不能重复。',
    zhHant: '候選項不能重複。',
    en: 'Options cannot be duplicated.',
    fr: 'Les options ne peuvent pas être dupliquées.',
    de: 'Optionen dürfen nicht doppelt vorkommen.',
    ja: '候補を重複させることはできません。',
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

  String get advancedJsonLabel => _m(
    zh: '完整决策配置（JSON）',
    zhHant: '完整決策設定（JSON）',
    en: 'Full decision configuration (JSON)',
    fr: 'Configuration complète de décision (JSON)',
    de: 'Vollständige Entscheidungskonfiguration (JSON)',
    ja: '完全な意思決定設定（JSON）',
  );

  String get choiceLinesLabel => _m(
    zh: '候选项，每行一个',
    zhHant: '候選項，每行一個',
    en: 'Options, one per line',
    fr: 'Options, une par ligne',
    de: 'Optionen, eine pro Zeile',
    ja: '候補（1 行に 1 つ）',
  );

  String get scoreLinesLabel => _m(
    zh: '评分等级，从低到高每行一个（2—10 级）',
    zhHant: '評分等級，從低到高每行一個（2—10 級）',
    en: 'Score levels, one per line from low to high (2–10)',
    fr: 'Niveaux de note, un par ligne du plus bas au plus haut (2–10)',
    de: 'Bewertungsstufen, eine pro Zeile von niedrig nach hoch (2–10)',
    ja: '評点等級（低い順、1 行に 1 つ、2〜10）',
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

  String get distribution => _m(
    zh: '概率分布',
    zhHant: '機率分布',
    en: 'Probability',
    fr: 'Probabilités',
    de: 'Wahrscheinlichkeit',
    ja: '確率分布',
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

  String get fenceRequest => _m(
    zh: '决策请求',
    zhHant: '決策請求',
    en: 'Decision request',
    fr: 'Requête de décision',
    de: 'Entscheidungsanfrage',
    ja: '意思決定リクエスト',
  );

  String get fenceResult => _m(
    zh: '决策结果',
    zhHant: '決策結果',
    en: 'Decision result',
    fr: 'Résultat de décision',
    de: 'Entscheidungsergebnis',
    ja: '意思決定の結果',
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
    if (value == DecisionPayload.simpleQuestionKey ||
        value.toLowerCase() == 'decision') {
      return simpleQuestionName;
    }
    if (value == DecisionPayload.fallbackQuestionKey) {
      return typeNoul;
    }
    return name;
  }

  String resultHeadline(Object? model) {
    final name = '$model'.trim();
    if (name.isEmpty || name == 'null') return resultTitle;
    return '$resultTitle · $name';
  }

  String heldProbability(num value) =>
      '$held · ${DecisionPayload.percentLabel(value)}';

  String choiceResult(Object? choice) =>
      '$typeChoice · ${displayValue(choice)}';

  String scoreResult(Object? score) => '$typeScore · ${displayValue(score)}';

  String confidenceLine(num value) =>
      '$confidence ${DecisionPayload.percentLabel(value)}';

  String probabilityAria(String label, num value) =>
      '$label ${DecisionPayload.percentLabel(value)} · $distribution';

  String displayValue(Object? value) {
    final text = DecisionPayload.displayText(value).trim();
    return text.isEmpty ? '—' : text;
  }
}
