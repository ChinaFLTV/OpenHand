import { t } from '../../i18n';
import { DECISION_MAX_CHARACTERS, DECISION_REQUEST, parseDecisionRequest } from './decision';

const literal = (text: string): string => text.replace(/[\\`*_{}\[\]()<>#+.!|~\-]/g, '\\$&').replace(/\r\n/g, '\n').replace(/\n/g, '  \n');
const valueText = (value: unknown): string => typeof value === 'string' ? literal(value)
  : '```json\n' + JSON.stringify(value, null, 2).replace(/`/g, '\\u0060') + '\n```';

/** 展示转换不修改消息原文；任一请求损坏时整体回退，避免遗漏输入。 */
export function decisionRequestToMarkdown(source: string): string | null {
  if (source.length > DECISION_MAX_CHARACTERS || !source.includes(DECISION_REQUEST)) return null;
  const matches = [...source.matchAll(/^```openhand-decision-request[ \t]*\r?\n([\s\S]*?)^```[ \t]*(?:\r?\n|$)/gm)];
  if (!matches.length) return null;
  const output: string[] = [];
  let end = 0;
  for (const match of matches) {
    const request = parseDecisionRequest(match[1]);
    if (!request) return null;
    output.push(literal(source.slice(end, match.index)));
    output.push(`### ${t('decision.request.title', '结构化决策')}\n\n**${t('decision.field.state', '待评估内容')}**\n\n${valueText(request.state)}`);
    for (const [name, question] of Object.entries(request.questions)) {
      const type = question.type;
      output.push(`#### ${literal(name)} · ${t(`decision.type.${type}`, type)}\n\n${valueText(question.instructions)}`);
      const criteria = question.criteria;
      if (criteria == null) continue;
      const label = type === 'score' ? t('decision.field.scoreLevels', '评分等级（从低到高）')
        : type === 'choice' ? t('decision.field.options', '候选项') : t('decision.field.criteria', '判断标准');
      const items = Object.entries(criteria);
      output.push(`**${label}**\n\n` + items.map(([key, value], index) => {
        const text = Array.isArray(criteria) ? valueText(value) : `${literal(key)}${value == null ? '' : typeof value === 'string' ? `：${valueText(value)}` : `\n\n${valueText(value)}`}`;
        return `${index + 1}. ${text.replace(/\n/g, '\n   ')}`;
      }).join('\n'));
    }
    end = match.index! + match[0].length;
  }
  output.push(literal(source.slice(end)));
  return output.join('\n\n').trim();
}
