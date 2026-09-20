import { useState } from 'preact/hooks';
import { useDialogExitMotion } from '../hooks/useDialogExitMotion';
import { t } from '../i18n';
import { decisionJsonDraft, initialDecisionDraft, DECISION_MAX_CHARACTERS, decisionDraft, decisionQuestionForType, type DecisionType } from '../shared/util/decision';
import { DialogActionButton, DialogFrame, DialogHeader, createStandardDialogFrameAppearance } from './DialogFrame';
import { DialogFooterActions } from './DialogChrome';
import { DecisionTypeSwitch } from './DecisionComposerForm';

export function DecisionRequestDialog({ initialText, onApply, onClose }: { initialText: string; onApply: (text: string) => void; onClose: () => void }) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const [initial] = useState(() => initialDecisionDraft(initialText));
  const [state, setState] = useState(initial.advanced ?? initial.state);
  const [question, setQuestion] = useState(initial.question);
  const [type, setType] = useState<DecisionType>(initial.type);
  const [criteriaByType, setCriteriaByType] = useState<Record<DecisionType, string>>(() => ({
    noul: '', choice: '', score: '', [initial.type]: initial.criteria,
  }));
  const criteria = criteriaByType[type];
  const [error, setError] = useState('');
  function updateType(next: DecisionType) {
    if (next === type) return;
    setType(next);
    setQuestion((current) => decisionQuestionForType(next, current));
    setError('');
  }
  function apply() {
    try { onApply(initial.advanced !== undefined ? decisionJsonDraft(state) : decisionDraft(state, question, type, criteria)); requestClose(); }
    catch (error) { setError(error instanceof Error ? error.message : t('decision.error.checkConfig', '请检查决策配置。')); }
  }
  return <DialogFrame closing={closing} onRequestClose={requestClose} ariaLabel={t('decision.dialog.title', '配置结构化决策')}
    {...createStandardDialogFrameAppearance({ panelClassName: 'w-full max-w-xl rounded-2xl overflow-hidden flex flex-col' })}>
    <DialogHeader title={t('decision.dialog.title', '配置结构化决策')} subtitle={t('decision.dialog.subtitle', '定义问题、候选项与评分标准')} onClose={requestClose} closeLabel={t('common.close', '关闭')} />
    <div class="overflow-auto min-h-0 p-5 space-y-4">
      <div class="oh-decision-dialog-note">{t('decision.dialog.body', '先提供待评估内容，再定义要选择、评分或判断的问题。配置会写入草稿，点击发送后才调用模型。')}</div>
      {initial.advanced === undefined && <DecisionTypeSwitch value={type} onChange={updateType} />}
      <label class="oh-decision-composer-field">{initial.advanced !== undefined ? <span class="oh-decision-field-label">{t('decision.field.advancedJson', '完整决策配置（JSON）')}</span> : <span class="oh-decision-field-label">{t('decision.field.state', '待评估内容')}</span>}
        <textarea class="oh-decision-input" rows={initial.advanced !== undefined ? 14 : 4} maxLength={DECISION_MAX_CHARACTERS} value={state} placeholder={initial.advanced !== undefined ? undefined : t('decision.field.stateHint', '粘贴或输入需要评估的文本')} onInput={(event) => setState(event.currentTarget.value)} />
      </label>
      {initial.advanced === undefined && <><label class="oh-decision-composer-field"><span class="oh-decision-field-label">{t('decision.field.question', '需要模型回答的问题')}</span>
        <textarea class="oh-decision-input" rows={2} value={question} placeholder={t('decision.field.questionHint', '一句话描述需要模型回答的问题')} onInput={(event) => setQuestion(event.currentTarget.value)} /></label>
      {type !== 'noul' && <label class="oh-decision-composer-field" key={type}><span class="oh-decision-field-label">{type === 'choice' ? t('decision.field.choiceLines', '候选项，每行一个') : t('decision.field.scoreLines', '评分等级，从低到高每行一个（2—10 级）')}</span>
        <textarea class="oh-decision-input" rows={4} value={criteria} placeholder={type === 'choice' ? t('decision.field.choiceHint', '例如：技术团队') : t('decision.field.scoreHint', '例如：一般')} onInput={(event) => { const value = event.currentTarget.value; setCriteriaByType(current => ({ ...current, [type]: value })); }} /></label>}
      </>}
      {error && <p role="alert" style={{ color: 'var(--m3-error)' }}>{error}</p>}
    </div>
    <DialogFooterActions variant="divided" className="oh-decision-actions"><DialogActionButton tone="secondary" onClick={requestClose}>{t('common.cancel', '取消')}</DialogActionButton><DialogActionButton tone="primary" onClick={apply} disabled={closing}>{t('decision.dialog.apply', '应用到草稿')}</DialogActionButton></DialogFooterActions>
  </DialogFrame>;
}
