import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { AnimatedList } from './AnimatedList';
import { t } from '../i18n';
import { DECISION_MAX_CRITERIA, DECISION_MAX_SCORE_LEVELS, DECISION_MIN_SCORE_LEVELS, DECISION_REQUEST, DECISION_SIMPLE_QUESTION_KEY, DECISION_TYPES, decisionDraft, decisionQuestionForType, initialDecisionDraft, type DecisionType } from '../shared/util/decision';

type Props = { initialText: string; disabled?: boolean; onChange: (text: string) => void };
type Criterion = { id: string; value: string };

function initialCriteria(initial: ReturnType<typeof initialDecisionDraft>, create: (value: string) => Criterion): Record<DecisionType, Criterion[]> {
  const values = initial.criteria.split('\n').filter(Boolean);
  return {
    noul: [],
    choice: (initial.type === 'choice' && values.length ? values : ['']).map(create),
    score: (initial.type === 'score' && values.length ? values : ['', '']).map(create),
  };
}

export function DecisionComposerForm({ initialText, disabled = false, onChange }: Props) {
  const initial = useMemo(() => initialDecisionDraft(initialText), [initialText]);
  const nextId = useRef(0);
  const createCriterion = (value: string): Criterion => ({ id: `criterion-${nextId.current++}`, value });
  const [state, setState] = useState(initial.state);
  const [question, setQuestion] = useState(initial.question);
  const [type, setType] = useState<DecisionType>(initial.type);
  const [criteriaByType, setCriteriaByType] = useState(() => initialCriteria(initial, createCriterion));
  const criteria = criteriaByType[type];
  const lastDraft = useRef(initialText);
  const loadingDraft = useRef(false);

  useEffect(() => {
    if (initialText === lastDraft.current) return;
    lastDraft.current = initialText;
    loadingDraft.current = true;
    setState(initial.state);
    setQuestion(initial.question);
    setType(initial.type);
    setCriteriaByType(initialCriteria(initial, createCriterion));
  }, [initialText, initial]);

  useEffect(() => {
    if (loadingDraft.current) {
      loadingDraft.current = false;
      return;
    }
    let draft: string;
    const values = criteria.map(item => item.value);
    try {
      draft = decisionDraft(state, question, type, values.join('\n'));
    } catch {
      const questionPayload = {
        type,
        instructions: question.trim(),
        ...(type === 'choice' ? { criteria: Object.fromEntries(values.filter(Boolean).map((item) => [item, null])) } : {}),
        ...(type === 'score' ? { criteria: values.filter(Boolean) } : {}),
      };
      const json = JSON.stringify({ state, questions: { [DECISION_SIMPLE_QUESTION_KEY]: questionPayload } }).replace(/`/g, '\\u0060');
      draft = `\`\`\`${DECISION_REQUEST}\n${json}\n\`\`\``;
    }
    if (draft === lastDraft.current) return;
    lastDraft.current = draft;
    onChange(draft);
  }, [state, question, type, criteria, initialText, onChange]);

  const updateType = (next: DecisionType) => {
    if (next === type) return;
    setType(next);
    setQuestion((current) => decisionQuestionForType(next, current));
  };
  const setCriteria = (update: (items: Criterion[]) => Criterion[]) => {
    if (disabled) return;
    setCriteriaByType(current => ({ ...current, [type]: update(current[type]) }));
  };
  const updateCriteria = (id: string, value: string) => setCriteria(items => items.map(item => item.id === id ? { ...item, value } : item));
  const removeCriteria = (id: string) => setCriteria(items => items.length > (type === 'score' ? DECISION_MIN_SCORE_LEVELS : 1) ? items.filter(item => item.id !== id) : items);
  const addCriteria = () => setCriteria(items => items.length < (type === 'score' ? DECISION_MAX_SCORE_LEVELS : DECISION_MAX_CRITERIA) ? [...items, createCriterion('')] : items);
  const moveCriteria = (id: string, direction: number) => setCriteria(items => {
    const index = items.findIndex(item => item.id === id);
    const target = index + direction;
    if (index < 0 || target < 0 || target >= items.length) return items;
    const next = [...items];
    next.splice(target, 0, ...next.splice(index, 1));
    return next;
  });

  return <div class="oh-decision-composer" aria-label={t('decision.request.title', '结构化决策')}>
    <div class="oh-decision-composer-heading">
      <span class="oh-decision-composer-icon" aria-hidden>
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
          <path d="M9 11l3 3L22 4" />
          <path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" />
        </svg>
      </span>
      <strong>{t('decision.request.title', '结构化决策')}</strong>
      <span>{t('decision.composer.hint', '发送时调用决策接口')}</span>
    </div>
    <label>{t('decision.field.state', '待评估内容')}<textarea class="oh-decision-input" rows={4} value={state} disabled={disabled} onInput={(event) => setState(event.currentTarget.value)} /></label>
    <label>{t('decision.field.question', '需要模型回答的问题')}<input class="oh-decision-field" value={question} disabled={disabled} onInput={(event) => setQuestion(event.currentTarget.value)} /></label>
    <div class="oh-decision-type-group" role="group" aria-label={t('decision.field.type', '决策类型')}>{DECISION_TYPES.map((value) => <button type="button" class="oh-decision-type" aria-pressed={type === value} disabled={disabled} onClick={() => updateType(value)}>{t(`decision.type.${value}`, value === 'noul' ? '判断' : value === 'choice' ? '选择' : '评分')}</button>)}</div>
    {type !== 'noul' ? <div class="oh-decision-criteria">
      <AnimatedList key={type} items={criteria} itemKey={item => item.id} className="oh-decision-criteria-list" renderItem={item => {
        const index = criteria.findIndex(current => current.id === item.id);
        const inactive = disabled || index < 0;
        const label = type === 'choice' ? t('decision.field.options', '候选项') : t('decision.field.scoreLevels', '评分等级（从低到高）');
        return <div class="oh-decision-criterion">
          <span>{index < 0 ? '−' : index + 1}</span>
          <input class="oh-decision-field" value={item.value} disabled={inactive} aria-label={label} placeholder={label} onInput={event => updateCriteria(item.id, event.currentTarget.value)} />
          <div class="oh-decision-reorder">
            <button type="button" aria-label={t('common.moveUp', '上移')} title={t('common.moveUp', '上移')} disabled={inactive || index === 0} onClick={() => moveCriteria(item.id, -1)}>⌃</button>
            <button type="button" aria-label={t('common.moveDown', '下移')} title={t('common.moveDown', '下移')} disabled={inactive || index === criteria.length - 1} onClick={() => moveCriteria(item.id, 1)}>⌄</button>
          </div>
          <button type="button" class="oh-decision-remove oh-tap-press" aria-label={t('common.delete', '删除')} title={t('common.delete', '删除')} disabled={inactive || criteria.length <= (type === 'score' ? DECISION_MIN_SCORE_LEVELS : 1)} onClick={() => removeCriteria(item.id)}>×</button>
        </div>;
      }} />
      <button type="button" class="oh-decision-add" disabled={disabled || criteria.length >= (type === 'score' ? DECISION_MAX_SCORE_LEVELS : DECISION_MAX_CRITERIA)} onClick={addCriteria}>＋ {type === 'choice' ? t('decision.composer.addChoice', '添加候选项') : t('decision.composer.addScore', '添加评分等级')}</button>
    </div> : null}
  </div>;
}
