import { render } from 'preact';
import { useState } from 'preact/hooks';
import { act } from 'preact/test-utils';
import { Markdown } from '../src/components/Markdown';
import { DecisionCard } from '../src/components/DecisionCard';
import { DecisionRequestDialog } from '../src/components/DecisionRequestDialog';
import { decisionJsonDraft, decisionDraft, initialDecisionDraft, parseDecisionResult } from '../src/shared/util/decision';
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
  verify(parseDecisionResult(JSON.stringify({ ...fixture, answers: { ...fixture.answers, 判断: { type: 'noul', noul: 2 } } })) === null, '无效概率不能显示为正常结果');
  await act(async () => render(<DecisionCard text={JSON.stringify(fixture)} />, root));
  verify(root.querySelectorAll('progress').length === 6, '决策卡片展示完整分布');
  await act(async () => root.querySelector<HTMLButtonElement>('button')!.click());
  verify(root.querySelector('button')?.getAttribute('aria-expanded') === 'false', '概率分布可折叠');
  await act(async () => render(<Markdown source={'```openhand-decision\n' + JSON.stringify(fixture) + '\n```'} />, root));
  await wait(200);
  verify(root.querySelectorAll('progress').length === 6, '实际 Markdown 消息入口渲染决策卡片');
  let applied = '';
  let closed = false;
  await act(async () => render(<DecisionRequestDialog initialText={draft} onApply={(text) => { applied = text; }} onClose={() => { closed = true; render(null, root); }} />, root));
  await wait(100);
  const apply = [...document.querySelectorAll<HTMLButtonElement>('button')].find(button => button.textContent === '应用到草稿');
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
