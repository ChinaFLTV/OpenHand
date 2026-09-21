import { useMemo, useState } from 'preact/hooks';
import { t } from '../i18n';
import {
  DECISION_FALLBACK_QUESTION_KEY,
  DECISION_SIMPLE_QUESTION_KEY,
  decisionDisplayText,
  decisionPercentLabel,
  decisionUnit,
  decisionQuestionForType,
  parseDecisionRequest,
  parseDecisionResult,
  type DecisionAnswer,
  type DecisionQuestion,
  type DecisionType,
} from '../shared/util/decision';

function typeLabel(type: string): string {
  if (type === 'choice') return t('decision.type.choice', '选择');
  if (type === 'score') return t('decision.type.score', '评分');
  return t('decision.type.noul', '判断');
}

function questionName(name: string): string {
  const value = name.trim();
  const lower = value.toLowerCase();
  if (value === DECISION_SIMPLE_QUESTION_KEY || lower === 'decision') {
    return t('decision.simpleName', '决策');
  }
  if (value === DECISION_FALLBACK_QUESTION_KEY || lower === 'noul' || lower === 'judgement' || lower === 'judgment') {
    return t('decision.type.noul', '判断');
  }
  if (lower === 'choice') return t('decision.type.choice', '选择');
  if (lower === 'score') return t('decision.type.score', '评分');
  return name;
}

function customQuestionName(name: string, type: string): string {
  const value = name.trim();
  const lower = value.toLowerCase();
  if (!value || value === DECISION_SIMPLE_QUESTION_KEY || lower === 'decision') return '';
  const named = questionName(name);
  return named === typeLabel(type) ? '' : named;
}

function localizedInstructions(type: string, instructions: unknown): string {
  if (typeof instructions !== 'string') return displayValue(instructions);
  if (type === 'choice' || type === 'score' || type === 'noul') {
    return decisionQuestionForType(type, instructions);
  }
  return instructions;
}

function questionCaption(name: string, type: string, instructions: unknown): string {
  const named = customQuestionName(name, type);
  const text = localizedInstructions(type, instructions);
  return named ? `${named} · ${text}` : text;
}

function displayValue(value: unknown): string {
  const text = decisionDisplayText(value).trim();
  return text || '—';
}

function DecisionTypeChip({ type }: { type: string }) {
  return <span class={`oh-decision-chip is-${type || 'noul'}`}>{typeLabel(type)}</span>;
}

function DecisionBar({ value, tone }: { value: number; tone: string }) {
  return <div class="oh-decision-bar-track" aria-hidden>
    <div class={`oh-decision-bar-fill is-${tone}`} style={{ width: `${decisionUnit(value) * 100}%` }} />
  </div>;
}

function probabilityEntries(answer: DecisionAnswer): Array<[string, number]> {
  if (answer.type === 'noul' && typeof answer.noul === 'number') {
    return [
      [t('decision.held', '成立'), answer.noul],
      [t('decision.notHeld', '不成立'), 1 - answer.noul],
    ];
  }
  return Object.entries(answer.probabilities ?? {}).map(([key, value]) => {
    const legend = answer.legend?.[key]?.trim();
    return [legend || key, value] as [string, number];
  });
}

function answerHeadline(answer: DecisionAnswer): string {
  if (answer.type === 'noul' && typeof answer.noul === 'number') {
    return `${t('decision.held', '成立')} · ${decisionPercentLabel(answer.noul)}`;
  }
  if (answer.type === 'choice') return displayValue(answer.choice);
  return displayValue(answer.score);
}

function DecisionAnswerCard({ name, question, answer, expanded }: { name: string; question: DecisionQuestion; answer: DecisionAnswer; expanded: boolean }) {
  const [open, setOpen] = useState(expanded);
  const [activated, setActivated] = useState(expanded);
  const [userToggled, setUserToggled] = useState(false);
  const entries = probabilityEntries(answer);
  const barTone = (label: string) => answer.type === 'noul' && label === t('decision.notHeld', '不成立') ? 'noul-no' : answer.type;
  return <section class={`oh-decision-block is-${answer.type || 'noul'}`}>
    <button type="button" class="oh-decision-toggle" aria-expanded={open} onClick={() => {
      setActivated(true);
      setUserToggled(true);
      setOpen(!open);
    }}>
      <span class="oh-decision-toggle-copy">
        <span class="oh-decision-toggle-meta">
          <DecisionTypeChip type={answer.type} />
          <span class="oh-decision-toggle-caption">{questionCaption(name, answer.type, question.instructions)}</span>
        </span>
        <strong class="oh-decision-toggle-result">{answerHeadline(answer)}</strong>
      </span>
      <span class="oh-decision-toggle-chevron" aria-hidden="true" />
    </button>
    <div class="oh-decision-distribution" style={{ gridTemplateRows: open ? '1fr' : '0fr', transition: userToggled ? undefined : 'none' }} aria-hidden={!open}>
      <div class="overflow-hidden min-h-0">{activated && <div class="oh-decision-distribution-body">
        {answer.confidence !== undefined && <p class="oh-decision-confidence">{t('decision.confidence', '置信度')} {decisionPercentLabel(answer.confidence)}</p>}
        {entries.map(([label, value]) => <div class="oh-decision-probability" key={label}>
          <div class="oh-decision-probability-meta"><span>{label}</span><span>{decisionPercentLabel(value)}</span></div>
          <DecisionBar value={value} tone={barTone(label)} />
        </div>)}
      </div>}</div>
    </div>
  </section>;
}

function CriteriaView({ type, criteria }: { type: DecisionType; criteria: unknown }) {
  if (criteria && typeof criteria === 'object' && !Array.isArray(criteria)) {
    return <div class="oh-decision-option-wrap">{Object.entries(criteria as Record<string, unknown>).map(([key, value]) => {
      const extra = value == null || String(value).trim() === '' ? '' : ` · ${value}`;
      return <span class={`oh-decision-option is-${type}`} key={key}>{key}{extra}</span>;
    })}</div>;
  }
  if (Array.isArray(criteria)) {
    return <ol class="oh-decision-score-list">{criteria.map((item, index) => <li key={`${index}-${item}`}><span>{index + 1}</span><p>{String(item)}</p></li>)}</ol>;
  }
  return null;
}

export function DecisionRequestCard({ text }: { text: string }) {
  const data = useMemo(() => parseDecisionRequest(text), [text]);
  if (!data) return <pre class="whitespace-pre-wrap break-words">{text}</pre>;
  const entries = Object.entries(data.questions);
  return <article class="oh-decision-card oh-decision-request">
    <div class="oh-decision-copy-field">
      <span>{t('decision.field.state', '待评估内容')}</span>
      <p>{displayValue(data.state)}</p>
    </div>
    {entries.length ? <div class="oh-decision-copy-field">
      <span>{entries.length === 1 ? t('decision.field.question', '需要模型回答的问题') : t('decision.field.questions', '决策问题')}</span>
    </div> : null}
    {entries.map(([name, question]) => {
      const named = customQuestionName(name, question.type);
      return <section class="oh-decision-request-question" key={name}>
        <div class="oh-decision-request-question-head">
          <DecisionTypeChip type={question.type} />
          {named ? <strong>{named}</strong> : null}
        </div>
        <p>{localizedInstructions(question.type, question.instructions)}</p>
        {question.criteria != null ? <>
          <span class="oh-decision-criteria-label">{question.type === 'score' ? t('decision.field.scoreLevels', '评分等级（从低到高）') : question.type === 'choice' ? t('decision.field.options', '候选项') : t('decision.field.criteria', '判断标准')}</span>
          <CriteriaView type={question.type} criteria={question.criteria} />
        </> : null}
      </section>;
    })}
  </article>;
}

export function DecisionCard({ text }: { text: string }) {
  const data = useMemo(() => parseDecisionResult(text), [text]);
  if (!data) return <pre class="whitespace-pre-wrap break-words">{text}</pre>;
  const entries = Object.entries(data.questions);
  if (!entries.length) return null;
  const cards = entries.flatMap(([name, question]) => {
    const answer = data.answers[name];
    return answer
      ? [<DecisionAnswerCard key={name} name={name} question={question} answer={answer} expanded={entries.length <= 3} />]
      : [];
  });
  if (!cards.length) return null;
  return cards.length === 1 ? cards[0] : <div class="oh-decision-stack">{cards}</div>;
}
