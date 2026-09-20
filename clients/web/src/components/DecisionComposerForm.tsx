import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import { AnimatedList } from './AnimatedList';
import { t } from '../i18n';
import { DECISION_MAX_CRITERIA, DECISION_MAX_SCORE_LEVELS, DECISION_MIN_SCORE_LEVELS, DECISION_REQUEST, DECISION_SIMPLE_QUESTION_KEY, DECISION_TYPES, decisionQuestionForType, initialDecisionDraft, localizedDecisionQuestion, type DecisionType } from '../shared/util/decision';

type Props = { initialText: string; disabled?: boolean; onChange: (text: string) => void };
type Criterion = { id: string; value: string };

function initialCriteria(initial: ReturnType<typeof initialDecisionDraft>, create: (value: string) => Criterion): Record<DecisionType, Criterion[]> {
  const values = initial.criteria.split('\n').filter(Boolean);
  return {
    noul: [],
    choice: (initial.type === 'choice' && values.length ? values : ['']).map(create),
    score: Array.from({ length: Math.max(DECISION_MIN_SCORE_LEVELS, initial.type === 'score' ? values.length : 0) },
      (_, index) => create(initial.type === 'score' ? values[index] ?? '' : '')),
  };
}

function DecisionTypeIcon({ type }: { type: DecisionType }) {
  return <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden>
    {type === 'choice' ? <>
      <path d="M8 6h13" /><path d="M8 12h13" /><path d="M8 18h13" />
      <path d="M3.5 6h.01" /><path d="M3.5 12h.01" /><path d="M3.5 18h.01" />
    </> : type === 'score' ? <path d="M12 3.2l2.5 6.4H21l-5.2 3.9 2 6.5L12 16.6 6.2 20l2-6.5L3 9.6h6.5z" /> : <>
      <path d="M9 11.5l3 3L21 6" /><circle cx="9" cy="13" r="6.2" />
    </>}
  </svg>;
}

export function DecisionTypeSwitch({ value, disabled = false, onChange }: { value: DecisionType; disabled?: boolean; onChange: (type: DecisionType) => void }) {
  return <div class="oh-decision-type-block">
    <span class="oh-decision-field-label">{t('decision.field.type', '决策类型')}</span>
    <div class="oh-decision-type-group" role="group" aria-label={t('decision.field.type', '决策类型')}>
      {DECISION_TYPES.map((type) => <button type="button" class="oh-decision-type" data-type={type} aria-pressed={value === type} disabled={disabled} onClick={() => onChange(type)}>
        <DecisionTypeIcon type={type} />
        {t(`decision.type.${type}`, type === 'noul' ? '判断' : type === 'choice' ? '选择' : '评分')}
      </button>)}
    </div>
  </div>;
}

export function DecisionComposerForm({ initialText, disabled = false, onChange }: Props) {
  const initial = useMemo(() => initialDecisionDraft(initialText), [initialText]);
  const nextId = useRef(0);
  const createCriterion = (value: string): Criterion => ({ id: `criterion-${nextId.current++}`, value });
  const [draft, setDraft] = useState(() => ({
    state: initial.state, question: initial.question, type: initial.type,
    criteriaByType: initialCriteria(initial, createCriterion),
  }));
  const draftRef = useRef(draft);
  const lastDraft = useRef(initialText);
  const { state, question, type, criteriaByType } = draft;
  const criteria = criteriaByType[type];
  const localizedQuestion = localizedDecisionQuestion(type);

  useLayoutEffect(() => {
    if (initialText === lastDraft.current) return;
    lastDraft.current = initialText;
    const next = {
      state: initial.state, question: initial.question, type: initial.type,
      criteriaByType: initialCriteria(initial, createCriterion),
    };
    draftRef.current = next;
    setDraft(next);
  }, [initialText, initial]);

  useEffect(() => {
    const current = draftRef.current;
    const nextQuestion = decisionQuestionForType(current.type, current.question);
    if (nextQuestion === current.question) return;
    const next = { ...current, question: nextQuestion };
    draftRef.current = next;
    setDraft(next);
  }, [localizedQuestion, type]);

  // 只有用户编辑才回写，挂载、语言更新和外部清空不会生成新草稿。
  const updateDraft = (update: Partial<typeof draft>) => {
    if (disabled) return;
    const next = { ...draftRef.current, ...update };
    draftRef.current = next;
    setDraft(next);
    const values = next.criteriaByType[next.type].map(item => item.value.trim()).filter(Boolean);
    const questionPayload = {
      type: next.type,
      instructions: next.question.trim(),
      ...(next.type === 'choice' ? { criteria: Object.fromEntries(values.map(value => [value, null])) } : {}),
      ...(next.type === 'score' ? { criteria: values } : {}),
    };
    const json = JSON.stringify({ state: next.state, questions: { [DECISION_SIMPLE_QUESTION_KEY]: questionPayload } }).replace(/`/g, '\\u0060');
    const encoded = `\`\`\`${DECISION_REQUEST}\n${json}\n\`\`\``;
    if (encoded === lastDraft.current) return;
    lastDraft.current = encoded;
    onChange(encoded);
  };
  const updateType = (next: DecisionType) => {
    if (next === draftRef.current.type) return;
    updateDraft({ type: next, question: decisionQuestionForType(next, draftRef.current.question) });
  };
  const setCriteria = (update: (items: Criterion[]) => Criterion[]) => {
    const current = draftRef.current;
    updateDraft({ criteriaByType: {
      ...current.criteriaByType, [current.type]: update(current.criteriaByType[current.type]),
    } });
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
  const criteriaLabel = type === 'choice' ? t('decision.field.options', '候选项') : t('decision.field.scoreLevels', '评分等级（从低到高）');
  const criteriaHint = type === 'choice' ? t('decision.field.choiceHint', '例如：技术团队') : t('decision.field.scoreHint', '例如：一般');

  return <div class={`oh-decision-composer is-${type}`} aria-label={t('decision.request.title', '结构化决策')}>
    <label class="oh-decision-composer-field">
      <span class="oh-decision-field-label">{t('decision.field.state', '待评估内容')}</span>
      <textarea class="oh-decision-input" rows={4} value={state} disabled={disabled} placeholder={t('decision.field.stateHint', '粘贴或输入需要评估的文本')} onInput={(event) => updateDraft({ state: event.currentTarget.value })} />
    </label>
    <label class="oh-decision-composer-field">
      <span class="oh-decision-field-label">{t('decision.field.question', '需要模型回答的问题')}</span>
      <input class="oh-decision-field" value={question} disabled={disabled} onInput={(event) => updateDraft({ question: event.currentTarget.value })} />
    </label>
    {DecisionTypeSwitch({ value: type, disabled, onChange: updateType })}
    {type !== 'noul' ? <div class="oh-decision-criteria">
      <span class="oh-decision-field-label">{criteriaLabel}</span>
      <AnimatedList key={type} items={criteria} itemKey={item => item.id} className="oh-decision-criteria-list" renderItem={item => {
        const index = criteria.findIndex(current => current.id === item.id);
        const inactive = disabled || index < 0;
        return <div class="oh-decision-criterion">
          <span>{index < 0 ? '−' : index + 1}</span>
          <input class="oh-decision-field" value={item.value} disabled={inactive} aria-label={criteriaLabel} placeholder={criteriaHint} onInput={event => updateCriteria(item.id, event.currentTarget.value)} />
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
