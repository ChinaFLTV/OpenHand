import { render } from 'preact';
import { useState } from 'preact/hooks';
import { act } from 'preact/test-utils';
import { DecisionComposerForm } from '../src/components/DecisionComposerForm';
import { initialDecisionDraft } from '../src/shared/util/decision';
import { syncLangFromAppPreferences } from '../src/i18n';
import '../src/styles/global.css';

syncLangFromAppPreferences('zh_Hans');
const initial = JSON.stringify({ state: '评估内容', questions: { 决策: { type: 'score', instructions: '评分', criteria: ['低', '中', '高'] } } });
let draft = initial;
function Showcase() {
  const [text, setText] = useState(initial);
  return <main style={{ maxWidth: 800, padding: 16, margin: 'auto' }}><DecisionComposerForm initialText={text} onChange={value => { draft = value; setText(value); }} /></main>;
}
const root = document.getElementById('qa-root')!;
const results: string[] = [];
const wait = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
const fields = () => [...root.querySelectorAll<HTMLInputElement>('.oh-decision-criterion input')];
function verify(value: unknown, label: string) { if (!value) throw new Error(label); results.push(label); }
try {
  await act(async () => render(<Showcase />, root));
  await wait(600);
  const first = fields()[0];
  const firstRow = first.closest('.oh-decision-criterion')!;
  const remove = firstRow.querySelector<HTMLButtonElement>('.oh-decision-remove')!;
  const indexBadge = firstRow.querySelector<HTMLSpanElement>('.oh-decision-index')!;
  verify(Math.abs(first.getBoundingClientRect().height - remove.getBoundingClientRect().height) < 1, '删除按钮与输入框等高');
  verify(Math.abs(indexBadge.getBoundingClientRect().width - remove.getBoundingClientRect().width) < 1, '序号与删除按钮同宽');
  verify(Math.abs(indexBadge.getBoundingClientRect().height - remove.getBoundingClientRect().height) < 1, '序号与删除按钮等高');
  verify(getComputedStyle(indexBadge).borderRadius === getComputedStyle(remove).borderRadius, '序号与删除按钮同圆角');
  first.focus();
  first.setSelectionRange(0, 1, 'backward');
  await act(async () => firstRow.querySelector<HTMLButtonElement>('[title="下移"]')!.click());
  verify(initialDecisionDraft(draft).criteria === '中\n低\n高', '排序即时更新草稿顺序');
  verify(fields()[1] === first, '排序保留输入节点');
  verify(document.activeElement === first, '排序保留输入焦点');
  verify(first.selectionStart === 0 && first.selectionEnd === 1 && first.selectionDirection === 'backward', '排序保留输入选区与选择方向');
  verify(root.getAnimations({ subtree: true }).length > 0, '排序播放位移动画');
  await wait(80);
  await act(async () => first.closest('.oh-decision-criterion')!.querySelector<HTMLButtonElement>('[title="上移"]')!.click());
  await wait(600);
  verify(fields()[0] === first, '动画中反向排序恢复正确位置');
  await act(async () => remove.click());
  verify(initialDecisionDraft(draft).criteria === '中\n高', '删除即时更新草稿');
  verify(root.querySelector('[inert]') != null, '退场条目不可交互');
  verify(document.activeElement !== first, '删除时不把焦点恢复到退场条目');
  await wait(600);
  verify(fields().length === 2 && !root.contains(first), '退场完成移除条目');
  await act(async () => root.querySelector<HTMLButtonElement>('.oh-decision-add')!.click());
  await wait(600);
  verify(fields().length === 3 && fields()[2].value === '', '新增空白行保留且进场完成');
  const types = [...root.querySelectorAll<HTMLButtonElement>('.oh-decision-type')];
  await act(async () => types[1].click());
  await wait(600);
  verify(fields().length === 1 && fields()[0].value === '', '候选项与评分条目隔离');
  await act(async () => types[2].click());
  await wait(600);
  verify(fields().map(field => field.value).join('|') === '中|高|', '切回恢复顺序和未完成条目');
  verify(root.getAnimations({ subtree: true }).length === 0, '动画收敛后无遗留任务');
  document.getElementById('qa-result')!.textContent = `通过 ${results.length} 项\n${results.join('\n')}`;
  document.documentElement.dataset.qa = 'passed';
} catch (error) {
  document.documentElement.dataset.qa = 'failed';
  document.getElementById('qa-result')!.textContent = String(error);
}
