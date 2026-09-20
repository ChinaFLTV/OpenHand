import { useMemo, useState } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { t } from '../i18n';
import {
  DECISION_FALLBACK_QUESTION_KEY,
  DECISION_MODEL_FALLBACK,
  DECISION_SIMPLE_QUESTION_KEY,
  decisionDisplayText,
  decisionPercentLabel,
  decisionUnit,
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
  if (value === DECISION_SIMPLE_QUESTION_KEY || value.toLowerCase() === 'decision') {
    return t('decision.simpleName', '决策');
  }
  if (value === DECISION_FALLBACK_QUESTION_KEY) return t('decision.type.noul', '判断');
  return name;
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

function DecisionChrome({
  kicker,
  title,
  subtitle,
  type,
  result,
  children,
}: {
  kicker: string;
  title: string;
  subtitle: string;
  type?: string;
  result?: boolean;
  children: ComponentChildren;
}) {
  return <article class={`oh-decision-card ${result ? 'is-result' : 'oh-decision-request'} is-${type || 'noul'}`}>
    <header class="oh-decision-card-header">
      <span class="oh-decision-card-icon" aria-hidden>
        {result ? (
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
            <path d="M4 19V5" />
            <path d="M4 19h16" />
            <path d="M7 14l3.2-4.2 2.6 2.4L17 7" />
          </svg>
        ) : (
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
            <path d="M9 11l3 3L22 4" />
            <path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" />
          </svg>
        )}
      </span>
      <div class="oh-decision-card-heading">
        <span class="oh-decision-kicker">{kicker}</span>
        <strong class="oh-decision-title">{title}</strong>
        <p class="oh-decision-subtitle">{subtitle}</p>
      </div>
      {type ? <DecisionTypeChip type={type} /> : null}
    </header>
    {children}
  </article>;
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
  if (answer.type === 'choice') return `${t('decision.type.choice', '选择')} · ${displayValue(answer.choice)}`;
  return `${t('decision.type.score', '评分')} · ${displayValue(answer.score)}`;
}

function DecisionAnswerCard({ name, question, answer, expanded }: { name: string; question: DecisionQuestion; answer: DecisionAnswer; expanded: boolean }) {
  const [open, setOpen] = useState(expanded);
  const [activated, setActivated] = useState(expanded);
  const entries = probabilityEntries(answer);
  const barTone = (label: string) => answer.type === 'noul' && label === t('decision.notHeld', '不成立') ? 'noul-no' : answer.type;
  return <section class="oh-decision-block">
    <button type="button" class="oh-decision-toggle" aria-expanded={open} onClick={() => { setActivated(true); setOpen(!open); }}>
      <span class="oh-decision-toggle-copy">
        <strong>{answerHeadline(answer)}</strong>
        <span>{questionName(name)} · {displayValue(question.instructions)}</span>
      </span>
      <DecisionTypeChip type={answer.type} />
    </button>
    <div class="oh-decision-distribution" style={{ gridTemplateRows: open ? '1fr' : '0fr' }} aria-hidden={!open}>
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
  const leadingType = entries.length === 1 ? entries[0][1].type : undefined;
  return <DecisionChrome
    kicker={t('decision.fence.request', '决策请求')}
    title={t('decision.request.title', '结构化决策')}
    subtitle={t('decision.request.subtitle', '待评估内容、问题与候选项已绑定到本次请求')}
    type={leadingType}
  >
    <div class="oh-decision-copy-field">
      <span>{t('decision.field.state', '待评估内容')}</span>
      <p>{displayValue(data.state)}</p>
    </div>
    <div class="oh-decision-copy-field">
      <span>{entries.length === 1 ? t('decision.field.question', '需要模型回答的问题') : t('decision.field.questions', '决策问题')}</span>
    </div>
    {entries.map(([name, question]) => <section class="oh-decision-block" key={name}>
      <div class="oh-decision-request-question">
        <div class="oh-decision-request-question-head">
          <strong>{questionName(name)}</strong>
          <DecisionTypeChip type={question.type} />
        </div>
        <p>{displayValue(question.instructions)}</p>
        {question.criteria != null ? <>
          <span class="oh-decision-criteria-label">{question.type === 'score' ? t('decision.field.scoreLevels', '评分等级（从低到高）') : question.type === 'choice' ? t('decision.field.options', '候选项') : t('decision.field.criteria', '判断标准')}</span>
          <CriteriaView type={question.type} criteria={question.criteria} />
        </> : null}
      </div>
    </section>)}
  </DecisionChrome>;
}

export function DecisionCard({ text }: { text: string }) {
  const data = useMemo(() => parseDecisionResult(text), [text]);
  if (!data) return <pre class="whitespace-pre-wrap break-words">{text}</pre>;
  const model = typeof data.model === 'string' && data.model.trim() ? data.model : DECISION_MODEL_FALLBACK;
  const entries = Object.entries(data.questions);
  return <DecisionChrome
    kicker={t('decision.fence.result', '决策结果')}
    title={`${t('decision.result.title', '决策结果')} · ${model}`}
    subtitle={t('decision.result.subtitle', '按问题查看答案与概率分布')}
    result
  >
    {entries.map(([name, question]) => <DecisionAnswerCard key={name} name={name} question={question} answer={data.answers[name]} expanded={entries.length <= 3} />)}
  </DecisionChrome>;
}
