import { useMemo, useState } from 'preact/hooks';
import { parseDecisionResult, type DecisionAnswer, type DecisionQuestion } from '../shared/util/decision';

function DecisionAnswerCard({ name, question, answer, expanded }: { name: string; question: DecisionQuestion; answer: DecisionAnswer; expanded: boolean }) {
  const [open, setOpen] = useState(expanded);
  const [activated, setActivated] = useState(expanded);
  const result = answer.type === 'noul' ? `成立概率 ${(answer.noul! * 100).toFixed(1)}%` : answer.type === 'choice' ? `选择：${answer.choice}` : `评分：${answer.score}`;
  const probabilities = answer.type === 'noul' ? { '成立': answer.noul!, '不成立': 1 - answer.noul! } : answer.probabilities!;
  return <section class="oh-decision-answer">
    <button type="button" class="oh-decision-toggle oh-tap-press" aria-expanded={open} onClick={() => { setActivated(true); setOpen(!open); }}>
      <strong>{result}</strong><span>{name} · {typeof question.instructions === 'string' ? question.instructions : JSON.stringify(question.instructions)}</span>
    </button>
    <div class="oh-decision-distribution" style={{ gridTemplateRows: open ? '1fr' : '0fr' }} aria-hidden={!open}>
      <div class="overflow-hidden min-h-0">{activated && <div class="p-3 space-y-2">
        {answer.confidence !== undefined && <p>置信度 {(answer.confidence * 100).toFixed(1)}%</p>}
        {Object.entries(probabilities).map(([key, value]) => <div key={key}>
          <div class="flex justify-between gap-3"><span>{typeof answer.legend?.[key] === 'string' ? answer.legend[key] : key}</span><span>{(value * 100).toFixed(1)}%</span></div>
          <progress aria-label={`${key} 概率`} max={1} value={value} class="oh-decision-progress" />
        </div>)}
      </div>}</div>
    </div>
  </section>;
}
export function DecisionCard({ text }: { text: string }) {
  const data = useMemo(() => parseDecisionResult(text), [text]);
  if (!data) return <pre class="whitespace-pre-wrap break-words">{text}</pre>;
  return <div class="oh-decision-card">
    <strong>决策结果 · {typeof data.model === 'string' ? data.model : 'Jev'}</strong>
    <p class="text-xs opacity-75 mt-1">按问题查看答案与概率分布。</p>
    {Object.entries(data.questions).map(([name, question]) => <DecisionAnswerCard key={name} name={name} question={question} answer={data.answers[name]} expanded={Object.keys(data.questions).length <= 3} />)}
  </div>;
}
