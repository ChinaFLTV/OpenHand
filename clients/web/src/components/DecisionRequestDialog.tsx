import { useState } from 'preact/hooks';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { decisionJsonDraft, initialDecisionDraft, DECISION_MAX_CHARACTERS, decisionDraft, decisionQuestionForType, type DecisionType } from '../shared/util/decision';
import { DialogActionButton, DialogFrame, DialogHeader, createStandardDialogFrameAppearance } from './DialogFrame';
import { DialogFooterActions } from './DialogChrome';

export function DecisionRequestDialog({ initialText, onApply, onClose }: { initialText: string; onApply: (text: string) => void; onClose: () => void }) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const [initial] = useState(() => initialDecisionDraft(initialText));
  const [state, setState] = useState(initial.advanced ?? initial.state);
  const [question, setQuestion] = useState(initial.question);
  const [type, setType] = useState<DecisionType>(initial.type);
  const [criteria, setCriteria] = useState(initial.criteria);
  const [error, setError] = useState('');
  function updateType(next: DecisionType) {
    if (next === type) return;
    setType(next);
    setQuestion((current) => decisionQuestionForType(next, current));
    setError('');
  }
  function apply() {
    try { onApply(initial.advanced !== undefined ? decisionJsonDraft(state) : decisionDraft(state, question, type, criteria)); requestClose(); }
    catch (error) { setError(error instanceof Error ? error.message : '请检查决策配置。'); }
  }
  return <DialogFrame closing={closing} onRequestClose={requestClose} ariaLabel="配置结构化决策"
    {...createStandardDialogFrameAppearance({ panelClassName: 'w-full max-w-xl rounded-2xl overflow-hidden flex flex-col' })}>
    <DialogHeader title="配置结构化决策" subtitle="定义问题、候选项与评分标准" onClose={requestClose} closeLabel="关闭" />
    <div class="overflow-auto min-h-0 p-5 space-y-4">
      <div class="oh-decision-card text-sm">提供待评估内容，并定义问题。应用后只更新草稿，点击发送才调用模型。</div>
      {initial.advanced === undefined && <div class="flex flex-wrap gap-2" role="group" aria-label="决策类型">{(['noul', 'choice', 'score'] as const).map((value) =>
        <button type="button" class="oh-decision-type oh-tap-press" aria-pressed={type === value} style={{ background: type === value ? 'var(--m3-primary-container)' : undefined }} onClick={() => updateType(value)}>{({noul: '判断', choice: '选择', score: '评分'})[value]}</button>)}</div>}
      <label class="block">{initial.advanced !== undefined ? '完整决策配置（JSON）' : '待评估内容'}<textarea class="oh-decision-input" rows={initial.advanced !== undefined ? 14 : 4} maxLength={DECISION_MAX_CHARACTERS} value={state} onInput={(event) => setState(event.currentTarget.value)} /></label>
      {initial.advanced === undefined && <><label class="block">需要模型回答的问题<textarea class="oh-decision-input" rows={2} value={question} onInput={(event) => setQuestion(event.currentTarget.value)} /></label>
      {type !== 'noul' && <label class="block">{type === 'choice' ? '候选项，每行一个' : '评分等级，从低到高每行一个（2—10 级）'}<textarea class="oh-decision-input" rows={4} value={criteria} onInput={(event) => setCriteria(event.currentTarget.value)} /></label>}
      </>}
      {error && <p role="alert" style={{ color: 'var(--m3-error)' }}>{error}</p>}
    </div>
    <DialogFooterActions variant="divided" className="oh-decision-actions"><DialogActionButton tone="secondary" onClick={requestClose}>取消</DialogActionButton><DialogActionButton tone="primary" onClick={apply} disabled={closing}>应用到草稿</DialogActionButton></DialogFooterActions>
  </DialogFrame>;
}
