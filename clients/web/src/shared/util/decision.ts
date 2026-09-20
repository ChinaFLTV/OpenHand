export const DECISION_REQUEST = 'openhand-decision-request';
export const DECISION_RESULT = 'openhand-decision';
export const DECISION_MAX_CHARACTERS = 1024 * 1024;
export const DEFAULT_DECISION_QUESTION = '根据所给信息，这段陈述是否成立？';
export type DecisionType = 'noul' | 'choice' | 'score';
export interface DecisionQuestion { type: DecisionType; instructions: unknown; criteria?: unknown }
export interface DecisionAnswer { type: DecisionType; noul?: number; choice?: string; score?: number; confidence?: number; probabilities?: Record<string, number>; legend?: Record<string, string> }
export interface DecisionResult { model?: string; answers: Record<string, DecisionAnswer>; questions: Record<string, DecisionQuestion> }
const object = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === 'object' && !Array.isArray(value);
const probability = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1;
export function decisionDraft(state: string, instructions: string, type: DecisionType, criteriaText: string): string {
  if (!state.trim() || !instructions.trim()) throw new Error('请填写待评估内容和决策问题。');
  const criteria = criteriaText.split('\n').map((line) => line.trim()).filter(Boolean);
  if (type === 'choice' && (!criteria.length || criteria.length > 255 || new Set(criteria).size !== criteria.length)) throw new Error('选择题需要 1 至 255 个不重复的候选项。');
  if (type === 'score' && (criteria.length < 2 || criteria.length > 10)) throw new Error('评分需要 2 至 10 个从低到高排列的等级。');
  const question = { type, instructions: instructions.trim(), ...(type === 'choice' ? { criteria: Object.fromEntries(criteria.map((key) => [key, null])) } : type === 'score' ? { criteria } : {}) };
  const json = JSON.stringify({ state: state.trim(), questions: { '决策': question } }).replace(/`/g, '\\u0060');
  if (json.length > DECISION_MAX_CHARACTERS) throw new Error('决策内容过长，请缩小输入范围。');
  return `\`\`\`${DECISION_REQUEST}\n${json}\n\`\`\``;
}
export function parseDecisionResult(text: string): DecisionResult | null {
  if (text.length > DECISION_MAX_CHARACTERS) return null;
  try {
    const data = JSON.parse(text);
    if (!object(data) || !object(data.answers) || !object(data.questions)) return null;
    const questions = Object.entries(data.questions);
    if (!questions.length || questions.length > 128) return null;
    for (const [key, question] of questions) {
      const answer = data.answers[key];
      if (!object(question) || !object(answer) || answer.type !== question.type) return null;
      if (answer.type === 'noul') { if (!probability(answer.noul)) return null; }
      else if (answer.type === 'choice' || answer.type === 'score') {
        if (!object(answer.probabilities) || !Object.keys(answer.probabilities).length || Object.keys(answer.probabilities).length > 255 || !Object.values(answer.probabilities).every(probability)) return null;
        if (answer.confidence !== undefined && !probability(answer.confidence)) return null;
        if (answer.type === 'choice' && (typeof answer.choice !== 'string' || !object(question.criteria) || !Object.hasOwn(question.criteria, answer.choice))) return null;
        if (answer.type === 'score' && (typeof answer.score !== 'number' || !Number.isFinite(answer.score))) return null;
      } else return null;
    }
    return data as unknown as DecisionResult;
  } catch { return null; }
}

export function initialDecisionDraft(text: string): { state: string; question: string; type: DecisionType; criteria: string; advanced?: string } {
  const fallback = { state: text, question: DEFAULT_DECISION_QUESTION, type: 'noul' as DecisionType, criteria: '' };
  const marker = `\`\`\`${DECISION_REQUEST}\n`;
  const start = text.indexOf(marker);
  if ((start < 0 && !text.trimStart().startsWith('{')) || text.length > DECISION_MAX_CHARACTERS) return fallback;
  try {
    const end = text.indexOf('```', start + marker.length);
    const payload = JSON.parse(start < 0 ? text : text.slice(start + marker.length, end));
    const advanced = { ...fallback, advanced: JSON.stringify(payload, null, 2) };
    if (typeof payload.state !== 'string' || !object(payload.questions) || Object.keys(payload.questions).length !== 1 || !Object.hasOwn(payload.questions, '决策')) return advanced;
    const question = Object.values(payload.questions)[0];
    if (!object(question) || typeof question.instructions !== 'string' || !['noul', 'choice', 'score'].includes(String(question.type))) return advanced;
    if (question.criteria !== undefined && !(question.type === 'choice' && object(question.criteria) && Object.values(question.criteria).every(value => value === null)) && !(question.type === 'score' && Array.isArray(question.criteria) && question.criteria.every(value => typeof value === 'string'))) return advanced;
    return { state: payload.state, question: question.instructions, type: question.type as DecisionType, criteria: Array.isArray(question.criteria) ? question.criteria.join('\n') : object(question.criteria) ? Object.keys(question.criteria).join('\n') : '' };
  } catch { return { ...fallback, advanced: text }; }
}

export function decisionJsonDraft(text: string): string {
  if (text.length > DECISION_MAX_CHARACTERS) throw new Error('决策内容过长，请缩小输入范围。');
  const payload = JSON.parse(text);
  const content = (value: unknown) => typeof value === 'string' ? !!value.trim() : object(value) || Array.isArray(value);
  if (!object(payload) || !content(payload.state) || !object(payload.questions)) throw new Error('请提供有效的 state 和 questions。');
  const questions = Object.entries(payload.questions);
  if (!questions.length || questions.length > 128) throw new Error('请配置 1 至 128 个决策问题。');
  for (const [key, question] of questions) {
    if (!key.trim() || !object(question) || !content(question.instructions)) throw new Error('请填写决策问题。');
    const criteria = question.criteria;
    if (question.type === 'choice') {
      if (!object(criteria) || !Object.keys(criteria).length || Object.keys(criteria).length > 255) throw new Error('选择题需要 1 至 255 个候选项。');
    } else if (question.type === 'score') {
      if (!Array.isArray(criteria) || criteria.length < 2 || criteria.length > 10) throw new Error('评分需要 2 至 10 个等级。');
    } else if (question.type !== 'noul' || (criteria != null && !object(criteria))) throw new Error('决策类型或判断标准无效。');
  }
  const json = JSON.stringify({ state: payload.state, questions: payload.questions }).replace(/`/g, '\\u0060');
  if (json.length > DECISION_MAX_CHARACTERS) throw new Error('决策内容过长，请缩小输入范围。');
  return `\`\`\`${DECISION_REQUEST}\n${json}\n\`\`\``;
}
