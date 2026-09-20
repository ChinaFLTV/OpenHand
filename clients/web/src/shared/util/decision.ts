import { t } from '../../i18n';

export const DECISION_REQUEST = 'openhand-decision-request';
export const DECISION_RESULT = 'openhand-decision';
const decisionResultFence = /^ {0,3}(?:`{3,}|~{3,})openhand-decision[ \t]*\r?$/m;
const decisionRequestFence = /^ {0,3}(?:`{3,}|~{3,})openhand-decision-request[ \t]*\r?$/m;

export function isStructuredDecisionMessage(message: { role: string; content: string }): boolean {
  if (!message.content.includes(DECISION_RESULT)) return false;
  return message.role === 'user' ? decisionRequestFence.test(message.content)
    : message.role === 'assistant' && decisionResultFence.test(message.content);
}
export const DECISION_MAX_CHARACTERS = 1024 * 1024;
export const DECISION_MAX_QUESTIONS = 128;
export const DECISION_MAX_CRITERIA = 255;
export const DECISION_MIN_SCORE_LEVELS = 2;
export const DECISION_MAX_SCORE_LEVELS = 10;
export const DECISION_SIMPLE_QUESTION_KEY = '决策';
export const DECISION_FALLBACK_QUESTION_KEY = '判断';
export const DECISION_MODEL_FALLBACK = 'Jev';
export type DecisionType = 'noul' | 'choice' | 'score';
export const DECISION_TYPES: readonly DecisionType[] = ['noul', 'choice', 'score'];

const BUILTIN_DECISION_QUESTIONS = new Set([
  '根据所给信息，这段陈述是否成立？',
  '根據所給資訊，這段陳述是否成立？',
  'Based on the given information, is this statement true?',
  'D’après les informations fournies, cette affirmation est-elle vraie ?',
  'Ist diese Aussage anhand der gegebenen Informationen zutreffend?',
  '提示された情報に基づき、この記述は成り立ちますか？',
  '根据所给信息，哪个候选项最符合？',
  '根據所給資訊，哪個候選項最符合？',
  'Based on the given information, which option fits best?',
  'D’après les informations fournies, quelle option convient le mieux ?',
  'Welche Option passt anhand der gegebenen Informationen am besten?',
  '提示された情報に基づき、どの候補が最も適切ですか？',
  '依据从低到高排列的等级，对所给内容评分。',
  '依據從低到高排列的等級，對所給內容評分。',
  'Score the given content using the levels ordered from low to high.',
  'Notez le contenu selon les niveaux, du plus bas au plus haut.',
  'Bewerten Sie den Inhalt anhand der Stufen von niedrig nach hoch.',
  '低い順に並べた等級で、提示された内容を評価してください。',
  'Given the information, does this statement hold?',
  'Given the information, which option fits best?',
  'Score the content using the levels listed from low to high.',
  '与えられた情報に基づき、この記述は成立しますか？',
  '与えられた情報に基づき、どの候補が最も当てはまりますか？',
  '低から高へ並んだレベルで、内容を採点してください。',
]);

export function decisionFenceLanguageLabel(lang: string): string | null {
  if (lang === DECISION_REQUEST) return t('decision.fence.request', '决策请求');
  if (lang === DECISION_RESULT) return t('decision.fence.result', '决策结果');
  return null;
}

export function localizedDecisionQuestion(type: DecisionType): string {
  return t(`decision.default.${type}`, type === 'choice'
    ? '根据所给信息，哪个候选项最符合？'
    : type === 'score'
      ? '依据从低到高排列的等级，对所给内容评分。'
      : '根据所给信息，这段陈述是否成立？');
}

export const DEFAULT_DECISION_QUESTION = '根据所给信息，这段陈述是否成立？';
export const DEFAULT_DECISION_QUESTIONS: Readonly<Record<DecisionType, string>> = {
  noul: DEFAULT_DECISION_QUESTION,
  choice: '根据所给信息，哪个候选项最符合？',
  score: '依据从低到高排列的等级，对所给内容评分。',
};

export function isBuiltInDecisionQuestion(text: string): boolean {
  return BUILTIN_DECISION_QUESTIONS.has(text.trim());
}

export function decisionQuestionForType(type: DecisionType, current = ''): string {
  const text = current.trim();
  return !text || isBuiltInDecisionQuestion(text) ? localizedDecisionQuestion(type) : current;
}

export interface DecisionQuestion { type: DecisionType; instructions: unknown; criteria?: unknown }
export interface DecisionAnswer { type: DecisionType; noul?: number; choice?: string; score?: number; confidence?: number; probabilities?: Record<string, number>; legend?: Record<string, string> }
export interface DecisionResult { model?: unknown; answers: Record<string, DecisionAnswer>; questions: Record<string, DecisionQuestion> }
export interface DecisionRequest { state: unknown; questions: Record<string, DecisionQuestion> }

const object = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === 'object' && !Array.isArray(value);
const probability = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1;

export function decisionUnit(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
  if (value <= 0) return 0;
  if (value >= 1) return 1;
  return value;
}

export function decisionPercentLabel(value: unknown): string {
  return `${(decisionUnit(value) * 100).toFixed(1)}%`;
}

export function decisionDisplayText(value: unknown): string {
  if (value == null) return '';
  if (typeof value === 'string') return value;
  try { return JSON.stringify(value, null, 2); } catch { return String(value); }
}

export function decisionDraft(state: string, instructions: string, type: DecisionType, criteriaText: string): string {
  if (!state.trim() || !instructions.trim()) throw new Error(t('decision.error.needStateQuestion', '请填写待评估内容和决策问题。'));
  const criteria = criteriaText.split('\n').map((line) => line.trim()).filter(Boolean);
  if (type === 'choice' && (!criteria.length || criteria.length > DECISION_MAX_CRITERIA || new Set(criteria).size !== criteria.length)) {
    throw new Error(t('decision.error.choiceUnique', '选择题需要 1 至 255 个不重复的候选项。'));
  }
  if (type === 'score' && (criteria.length < DECISION_MIN_SCORE_LEVELS || criteria.length > DECISION_MAX_SCORE_LEVELS)) {
    throw new Error(t('decision.error.scoreCount', '评分需要 2 至 10 个从低到高排列的等级。'));
  }
  const question = { type, instructions: instructions.trim(), ...(type === 'choice' ? { criteria: Object.fromEntries(criteria.map((key) => [key, null])) } : type === 'score' ? { criteria } : {}) };
  const json = JSON.stringify({ state: state.trim(), questions: { [DECISION_SIMPLE_QUESTION_KEY]: question } }).replace(/`/g, '\\u0060');
  if (json.length > DECISION_MAX_CHARACTERS) throw new Error(t('decision.error.tooLong', '决策内容过长，请缩小输入范围。'));
  return `\`\`\`${DECISION_REQUEST}\n${json}\n\`\`\``;
}

export function parseDecisionResult(text: string): DecisionResult | null {
  if (text.length > DECISION_MAX_CHARACTERS) return null;
  try {
    const data = JSON.parse(text);
    if (!object(data) || !object(data.answers) || !object(data.questions)) return null;
    const questions = Object.entries(data.questions);
    if (!questions.length || questions.length > DECISION_MAX_QUESTIONS) return null;
    for (const [key, question] of questions) {
      const answer = data.answers[key];
      if (!object(question) || !object(answer) || answer.type !== question.type) return null;
      if (answer.type === 'noul') { if (!probability(answer.noul)) return null; }
      else if (answer.type === 'choice' || answer.type === 'score') {
        if (!object(answer.probabilities) || !Object.keys(answer.probabilities).length || Object.keys(answer.probabilities).length > DECISION_MAX_CRITERIA || !Object.values(answer.probabilities).every(probability)) return null;
        if (answer.confidence !== undefined && !probability(answer.confidence)) return null;
        if (answer.type === 'choice' && (typeof answer.choice !== 'string' || !object(question.criteria) || !Object.hasOwn(question.criteria, answer.choice))) return null;
        if (answer.type === 'score' && (typeof answer.score !== 'number' || !Number.isFinite(answer.score))) return null;
      } else return null;
    }
    return data as unknown as DecisionResult;
  } catch { return null; }
}

export function parseDecisionRequest(text: string): DecisionRequest | null {
  if (text.length > DECISION_MAX_CHARACTERS) return null;
  try {
    const marker = `\`\`\`${DECISION_REQUEST}\n`;
    const start = text.indexOf(marker);
    const payload = JSON.parse(start >= 0 ? text.slice(start + marker.length, text.indexOf('```', start + marker.length)) : text);
    if (!object(payload) || !object(payload.questions)) return null;
    const questions = Object.entries(payload.questions);
    if (!questions.length || questions.length > DECISION_MAX_QUESTIONS) return null;
    const parsed: Record<string, DecisionQuestion> = {};
    for (const [key, question] of questions) {
      if (!key.trim() || !object(question) || !['noul', 'choice', 'score'].includes(String(question.type))) return null;
      const instructions = question.instructions;
      const hasInstructions = typeof instructions === 'string' ? !!instructions.trim() : object(instructions) || Array.isArray(instructions);
      if (!hasInstructions) return null;
      const criteria = question.criteria;
      if (question.type === 'choice') {
        if (!object(criteria) || !Object.keys(criteria).length || Object.keys(criteria).length > DECISION_MAX_CRITERIA) return null;
      } else if (question.type === 'score') {
        if (!Array.isArray(criteria) || criteria.length < DECISION_MIN_SCORE_LEVELS || criteria.length > DECISION_MAX_SCORE_LEVELS) return null;
      } else if (criteria != null && !object(criteria)) return null;
      parsed[key] = question as unknown as DecisionQuestion;
    }
    const state = payload.state;
    if (!(typeof state === 'string' ? !!state.trim() : object(state) || Array.isArray(state))) return null;
    return { state, questions: parsed };
  } catch { return null; }
}

export function initialDecisionDraft(text: string): { state: string; question: string; type: DecisionType; criteria: string; advanced?: string } {
  const fallback = { state: text, question: localizedDecisionQuestion('noul'), type: 'noul' as DecisionType, criteria: '' };
  const marker = `\`\`\`${DECISION_REQUEST}\n`;
  const start = text.indexOf(marker);
  if ((start < 0 && !text.trimStart().startsWith('{')) || text.length > DECISION_MAX_CHARACTERS) return fallback;
  try {
    const end = text.indexOf('```', start + marker.length);
    const payload = JSON.parse(start < 0 ? text : text.slice(start + marker.length, end));
    const advanced = { ...fallback, advanced: JSON.stringify(payload, null, 2) };
    if (typeof payload.state !== 'string' || !object(payload.questions) || Object.keys(payload.questions).length !== 1 || !Object.hasOwn(payload.questions, DECISION_SIMPLE_QUESTION_KEY)) return advanced;
    const question = Object.values(payload.questions)[0];
    if (!object(question) || typeof question.instructions !== 'string' || !['noul', 'choice', 'score'].includes(String(question.type))) return advanced;
    if (question.criteria !== undefined && !(question.type === 'choice' && object(question.criteria) && Object.values(question.criteria).every(value => value === null)) && !(question.type === 'score' && Array.isArray(question.criteria) && question.criteria.every(value => typeof value === 'string'))) return advanced;
    return { state: payload.state, question: question.instructions, type: question.type as DecisionType, criteria: Array.isArray(question.criteria) ? question.criteria.join('\n') : object(question.criteria) ? Object.keys(question.criteria).join('\n') : '' };
  } catch { return { ...fallback, advanced: text }; }
}

export function decisionJsonDraft(text: string): string {
  if (text.length > DECISION_MAX_CHARACTERS) throw new Error(t('decision.error.tooLong', '决策内容过长，请缩小输入范围。'));
  const payload = JSON.parse(text);
  const content = (value: unknown) => typeof value === 'string' ? !!value.trim() : object(value) || Array.isArray(value);
  if (!object(payload) || !content(payload.state) || !object(payload.questions)) throw new Error(t('decision.error.needStateQuestions', '请提供有效的待评估内容和问题。'));
  const questions = Object.entries(payload.questions);
  if (!questions.length || questions.length > DECISION_MAX_QUESTIONS) throw new Error(t('decision.error.questionCount', '请配置 1 至 128 个决策问题。'));
  for (const [key, question] of questions) {
    if (!key.trim() || !object(question) || !content(question.instructions)) throw new Error(t('decision.error.needInstructions', '请填写决策问题。'));
    const criteria = question.criteria;
    if (question.type === 'choice') {
      if (!object(criteria) || !Object.keys(criteria).length || Object.keys(criteria).length > DECISION_MAX_CRITERIA) throw new Error(t('decision.error.choiceCount', '选择题需要 1 至 255 个候选项。'));
    } else if (question.type === 'score') {
      if (!Array.isArray(criteria) || criteria.length < DECISION_MIN_SCORE_LEVELS || criteria.length > DECISION_MAX_SCORE_LEVELS) throw new Error(t('decision.error.scoreCount', '评分需要 2 至 10 个从低到高排列的等级。'));
    } else if (question.type !== 'noul' || (criteria != null && !object(criteria))) throw new Error(t('decision.error.badType', '决策类型或判断标准无效。'));
  }
  const json = JSON.stringify({ state: payload.state, questions: payload.questions }).replace(/`/g, '\\u0060');
  if (json.length > DECISION_MAX_CHARACTERS) throw new Error(t('decision.error.tooLong', '决策内容过长，请缩小输入范围。'));
  return `\`\`\`${DECISION_REQUEST}\n${json}\n\`\`\``;
}
