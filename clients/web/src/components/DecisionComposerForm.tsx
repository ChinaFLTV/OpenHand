import { useEffect, useMemo, useState } from 'preact/hooks';
import { DECISION_REQUEST, decisionDraft, initialDecisionDraft, type DecisionType } from '../shared/util/decision';

type Props = { initialText: string; disabled?: boolean; onChange: (text: string) => void };

export function DecisionComposerForm({ initialText, disabled = false, onChange }: Props) {
  const initial = useMemo(() => initialDecisionDraft(initialText), [initialText]);
  const [state, setState] = useState(initial.state);
  const [question, setQuestion] = useState(initial.question);
  const [type, setType] = useState<DecisionType>(initial.type);
  const [criteria, setCriteria] = useState<string[]>(() => initial.criteria.split('\n').filter(Boolean));

  useEffect(() => {
    setState(initial.state);
    setQuestion(initial.question);
    setType(initial.type);
    setCriteria(initial.criteria.split('\n').filter(Boolean));
  }, [initial.state, initial.question, initial.type, initial.criteria]);

  useEffect(() => {
    try {
      onChange(decisionDraft(state, question, type, criteria.join('\n')));
    } catch {
      const questionPayload = {
        type,
        instructions: question.trim(),
        ...(type === 'choice' ? { criteria: Object.fromEntries(criteria.filter(Boolean).map((item) => [item, null])) } : {}),
        ...(type === 'score' ? { criteria: criteria.filter(Boolean) } : {}),
      };
      const json = JSON.stringify({ state, questions: { 决策: questionPayload } }).replace(/`/g, '\\u0060');
      onChange(`\`\`\`${DECISION_REQUEST}\n${json}\n\`\`\``);
    }
  }, [state, question, type, criteria, onChange]);

  const updateType = (next: DecisionType) => {
    setType(next);
    setCriteria((items) => next === 'noul' ? [] : items.length ? items : next === 'score' ? ['', ''] : ['']);
  };
  const updateCriteria = (index: number, value: string) => setCriteria((items) => items.map((item, i) => i === index ? value : item));
  const removeCriteria = (index: number) => setCriteria((items) => items.length > (type === 'score' ? 2 : 1) ? items.filter((_, i) => i !== index) : items);
  const addCriteria = () => setCriteria((items) => items.length < (type === 'score' ? 10 : 255) ? [...items, ''] : items);

  return <div class="oh-decision-composer" aria-label="结构化决策">
    <div class="oh-decision-composer-heading"><span class="oh-decision-composer-icon" aria-hidden>决</span><strong>结构化决策</strong><span>发送时调用模型</span></div>
    <label>待评估内容<textarea class="oh-decision-input" rows={4} value={state} disabled={disabled} onInput={(event) => setState(event.currentTarget.value)} /></label>
    <label>需要模型回答的问题<input class="oh-decision-field" value={question} disabled={disabled} onInput={(event) => setQuestion(event.currentTarget.value)} /></label>
    <div class="oh-decision-type-group" role="group" aria-label="决策类型">{(['noul', 'choice', 'score'] as const).map((value) => <button type="button" class="oh-decision-type oh-tap-press" aria-pressed={type === value} disabled={disabled} onClick={() => updateType(value)}>{({ noul: '判断', choice: '选择', score: '评分' })[value]}</button>)}</div>
    {type !== 'noul' ? <div class="oh-decision-criteria">
      {criteria.map((value, index) => <div class="oh-decision-criterion" key={`${type}-${index}`}><span>{index + 1}</span><input class="oh-decision-field" value={value} disabled={disabled} placeholder={type === 'choice' ? '候选项' : '评分等级（从低到高）'} onInput={(event) => updateCriteria(index, event.currentTarget.value)} /><button type="button" class="oh-decision-remove" aria-label="删除此项" disabled={disabled || criteria.length <= (type === 'score' ? 2 : 1)} onClick={() => removeCriteria(index)}>×</button></div>)}
      <button type="button" class="oh-decision-add oh-tap-press" disabled={disabled} onClick={addCriteria}>＋ {type === 'choice' ? '添加候选项' : '添加评分等级'}</button>
    </div> : null}
  </div>;
}
