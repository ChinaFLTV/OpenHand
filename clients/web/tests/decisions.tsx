import { render } from 'preact';
import { useState } from 'preact/hooks';
import { act } from 'preact/test-utils';
import { Markdown } from '../src/components/Markdown';
import { DecisionCard } from '../src/components/DecisionCard';
import { DecisionRequestDialog } from '../src/components/DecisionRequestDialog';
import { MessageCard } from '../src/components/MessageCard';
import { t } from '../src/i18n';
import { decisionJsonDraft, decisionDraft, decisionResultInfoItems, initialDecisionDraft, parseDecisionRequest, parseDecisionResult, parseDecisionResultFromMessage } from '../src/shared/util/decision';
import '../src/styles/global.css';

// 固定合成样例仅用于交互验证，不代表真实模型输出。
const fixture = { model: 'Jev · 测试样例', questions: { 分类: { type: 'choice', instructions: '由哪个部门处理？', criteria: { 技术: null, 财务: null } }, 判断: { type: 'noul', instructions: '是否紧急？' }, 评分: { type: 'score', instructions: '优先级', criteria: ['低', '高'] } }, answers: { 分类: { type: 'choice', choice: '技术', probabilities: { 技术: .8, 财务: .2 }, confidence: .7 }, 判断: { type: 'noul', noul: .65 }, 评分: { type: 'score', score: .4, probabilities: { '0': .6, '1': .4 }, legend: { '0': '低', '1': '高' }, confidence: .2 } } };
function Showcase() {
  const [open, setOpen] = useState(false);
  return <main style={{ maxWidth: 680, padding: 20, margin: 'auto' }}>
    <h1>结构化决策 · 测试样例</h1>
    <button class="oh-composer-control" onClick={() => setOpen(true)}>打开配置样例</button>
    <DecisionCard text={JSON.stringify(fixture)} />
    {open && <DecisionRequestDialog initialText="这是一条待判断的测试陈述。" onApply={() => {}} onClose={() => setOpen(false)} />}
  </main>;
}
const root = document.getElementById('qa-root')!;
const results: string[] = [];
const wait = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
function verify(value: unknown, label: string) { if (!value) throw new Error(label); results.push(label); }
try {
  const draft = decisionDraft('待判断内容 `代码`', '是否成立？', 'choice', '甲\n乙');
  verify(initialDecisionDraft(draft).criteria === '甲\n乙', '重新打开配置保留候选项');
  verify(initialDecisionDraft(draft).state === '待判断内容 `代码`', '围栏与反引号安全往返');
  const advanced = decisionJsonDraft(JSON.stringify({ state: { 内容: '批量' }, questions: fixture.questions }));
  verify(initialDecisionDraft(advanced).advanced?.includes('财务'), '复杂配置保留问题名称和结构');
  verify(parseDecisionResult(JSON.stringify(fixture)), '三类响应均能解析');
  verify(parseDecisionRequest(JSON.stringify({ state: '待判断内容', questions: { 判断: { type: 'noul', instructions: '是否紧急？' } } })), '请求载荷可解析');
  verify(parseDecisionResult(JSON.stringify({ ...fixture, answers: { ...fixture.answers, 判断: { type: 'noul', noul: 2 } } })) === null, '无效概率不能显示为正常结果');
  await act(async () => render(<DecisionCard text={JSON.stringify(fixture)} />, root));
  verify(root.querySelectorAll('.oh-decision-bar-fill').length === 6, '决策卡片展示完整分布');
  verify(!root.querySelector('.oh-decision-card-header'), '结果卡片去掉顶部图标与标题');
  verify(!root.querySelector('.oh-decision-card'), '结果不再套一层父卡片');
  verify(root.querySelectorAll('.oh-decision-block').length === 3, '每个问题各自成卡');
  verify(!root.querySelector('.oh-decision-toggle'), '结果卡片不再折叠');
  verify(!root.querySelector('.oh-decision-chip'), '结果卡片去掉类型胶囊');
  verify(!root.querySelector('.oh-decision-confidence'), '结果卡片去掉置信度');
  verify(!root.textContent?.includes(t('decision.confidence', '置信度')), '置信度不在结果卡片正文');
  verify(!root.textContent?.includes('由哪个部门处理？'), '结果卡片不重复提问');
  const englishBuiltIn = {
    questions: { choice: { type: 'choice', instructions: 'Based on the given information, which option fits best?', criteria: { 甲: null } } },
    answers: { choice: { type: 'choice', choice: '甲', probabilities: { 甲: 1 }, confidence: 0.99 } },
  };
  await act(async () => render(<DecisionCard text={JSON.stringify(englishBuiltIn)} />, root));
  verify(!root.querySelector('.oh-decision-chip'), '结果卡片不显示类型胶囊');
  verify(!root.textContent?.includes(t('decision.default.choice', '根据所给信息，哪个候选项最符合？')), '结果卡片不重复内置提问');
  verify(!root.textContent?.includes(t('decision.confidence', '置信度')), '置信度不在结果卡片');
  verify(root.textContent?.includes('甲'), '候选项概率条保留');
  const fenced = '```openhand-decision\n' + JSON.stringify(fixture) + '\n```';
  verify(parseDecisionResultFromMessage(fenced), '围栏结果可解析');
  const info = decisionResultInfoItems(fenced);
  verify(info.some((item) => item.label === t('decision.type.choice', '选择')), '第二排包含选择类型');
  verify(info.some((item) => item.label === t('decision.type.score', '评分')), '第二排包含评分类型');
  verify(info.some((item) => item.label === t('decision.type.noul', '判断')), '第二排包含判断类型');
  verify(info.some((item) => item.label === '0.4'), '第二排包含评分元数据');
  verify(info.some((item) => item.label === `${t('decision.confidence', '置信度')} 70.0%`), '第二排包含置信度');
  await act(async () => render(<MessageCard active onCopy={() => {}} message={{
    id: 'jev-result', role: 'assistant', kind: 'assistant', content: fenced,
    character_count: fenced.length, created_at: '2026-09-21T04:02:00Z', model_label: 'jev-latest',
  }} />, root));
  await wait(200);
  const selectedLabels = [...root.querySelectorAll('.oh-message-selected-info-row .oh-message-info-button')].map((node) => node.textContent ?? '');
  verify(selectedLabels.some((label) => label.includes(t('decision.type.choice', '选择'))), '选中后第二排显示类型胶囊');
  verify(selectedLabels.some((label) => label.includes(t('decision.confidence', '置信度'))), '选中后第二排显示置信度');
  verify(selectedLabels.some((label) => label.includes('0.4')), '选中后第二排显示评分');
  verify(selectedLabels.some((label) => label.includes('jev-latest')), '选中后第二排仍显示模型');
  await act(async () => render(<Markdown source={fenced} />, root));
  await wait(200);
  verify(root.querySelectorAll('.oh-decision-bar-fill').length === 6, '实际 Markdown 消息入口渲染决策卡片');
  const requestFence = '```openhand-decision-request\n' + JSON.stringify({ state: '待判断内容', questions: { 判断: { type: 'noul', instructions: '是否紧急？' } } }) + '\n```';
  await act(async () => render(<Markdown source={requestFence} />, root));
  await wait(200);
  verify(root.querySelector('.oh-decision-request'), '请求围栏渲染为决策请求卡片');
  verify(!root.querySelector('.oh-decision-request .oh-decision-card-header'), '请求卡片去掉顶部图标与标题');
  verify(!root.querySelector('.oh-decision-request .oh-decision-block'), '请求不再嵌套子卡片');
  verify(root.querySelector('.oh-decision-request-question-head .oh-decision-chip'), '请求类型胶囊在左侧');
  let applied = '';
  let closed = false;
  await act(async () => render(<DecisionRequestDialog initialText={draft} onApply={(text) => { applied = text; }} onClose={() => { closed = true; render(null, root); }} />, root));
  await wait(100);
  const apply = [...document.querySelectorAll<HTMLButtonElement>('button')].find(button => button.textContent === t('decision.dialog.apply', '应用到草稿'));
  verify(apply, '真实弹窗提供应用操作');
  await act(async () => apply!.click());
  await wait(1800);
  verify(closed && !document.querySelector('[role="dialog"]'), '退场后释放弹窗与遮罩');
  verify(initialDecisionDraft(applied).type === 'choice', '应用草稿保持决策类型');
  await act(async () => render(<Showcase />, root));
  document.getElementById('qa-result')!.textContent = `通过 ${results.length} 项\n${results.join('\n')}`;
  document.documentElement.dataset.qa = 'passed';
} catch (error) {
  document.documentElement.dataset.qa = 'failed';
  document.getElementById('qa-result')!.textContent = String(error);
}
