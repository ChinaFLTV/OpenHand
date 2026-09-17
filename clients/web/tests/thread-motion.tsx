import { render } from 'preact';
import { useState } from 'preact/hooks';
import { act } from 'preact/test-utils';
import { AnimatedList } from '../src/components/AnimatedList';
import { AnimatedTitleText } from '../src/components/AnimatedTitleText';
import { syncRemoteDialogMotionSettings } from '../src/hooks/useDialogMotionSettings';
import '../src/styles/global.css';

const root = document.getElementById('qa-root')!;
const result = document.getElementById('qa-result')!;
const results: string[] = [];
const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
function verify(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
  results.push(message);
}
interface Row { id: string; title: string }
let updateRows!: (rows: Row[]) => void;
let updateTitle!: (text: string) => void;
const a = { id: 'a', title: '排查系统盘日志写满与崩溃' };
const b = { id: 'b', title: '分析网络延迟与服务稳定性' };
const c = { id: 'c', title: '检查应用性能与动画效果' };
const row = (id: string) => root.querySelector<HTMLElement>(`[data-presence-key="${id}"]`);
function ListProbe() {
  const [rows, setRows] = useState([a, b]);
  updateRows = setRows;
  return <div style={{ width: '340px', padding: '24px' }}>
    <AnimatedList items={rows} itemKey={(item) => item.id} empty={<p>暂无会话</p>}
      renderItem={(item) => <div class="oh-sessions-card rounded-m3-md p-4"
        style={{ background: 'var(--m3-primary-container)' }}>
        <AnimatedTitleText text={item.title} />
        <button style={{ display: 'block' }}>打开会话</button>
      </div>} />
  </div>;
}
function TitleProbe() {
  const [title, setTitle] = useState('原始标题');
  updateTitle = setTitle;
  return <AnimatedTitleText text={title} animateOnMount />;
}

function ComposerCollapseProbe() {
  const [collapsed, setCollapsed] = useState(false);
  return <section
    class="oh-session-composer rounded-xl p-4"
    data-collapsed={collapsed ? 'true' : 'false'}
    style={{ width: '680px', background: 'var(--m3-surface-container)', boxShadow: 'var(--m3-elev-1)' }}
  >
    <div class="oh-composer-toolbar" data-collapsed={collapsed ? 'true' : 'false'}>
      <button
        type="button"
        class="oh-composer-icon-control oh-composer-collapse-control"
        onClick={() => setCollapsed((value) => !value)}
      >
        折叠
      </button>
    </div>
    <div class="oh-composer-body" data-collapsed={collapsed ? 'true' : 'false'}>
      <div style={{ height: '220px', padding: '18px', background: 'var(--m3-surface)' }}>
        输入区内容
      </div>
    </div>
    <div
      class="oh-composer-footer"
      data-collapsed={collapsed ? 'true' : 'false'}
      style={{ height: '64px', marginTop: '12px' }}
    >
      输入区操作栏
    </div>
  </section>;
}

function Demo() {
  const [rows, setRows] = useState([a, b, c]);
  const [selected, setSelected] = useState(a.id);
  const current = rows.find((item) => item.id === selected) ?? rows[0];
  return <main style={{ padding: '28px', minHeight: '100vh', background: 'var(--m3-surface)' }}>
    <div style={{ display: 'flex', gap: '20px', alignItems: 'flex-start' }}>
      <aside style={{ width: '300px', padding: '16px', border: '1px solid var(--m3-outline)', borderRadius: '28px', background: 'var(--m3-surface-container)' }}>
        <h2 style={{ padding: '0 8px 12px', fontWeight: 700 }}>线程</h2>
        <AnimatedList items={rows} itemKey={(item) => item.id} empty={<p>暂无会话</p>}
          renderItem={(item) => <button onClick={() => setSelected(item.id)}
            style={{ width: '100%', textAlign: 'left', padding: '14px', borderRadius: '24px', background: current?.id === item.id ? 'var(--m3-primary-container)' : 'transparent' }}>
            <AnimatedTitleText text={item.title} className="w-full" />
          </button>} />
      </aside>
      <section style={{ flex: 1, minWidth: 0, padding: '24px', borderRadius: '28px', background: 'var(--m3-surface-container)' }}>
        <AnimatedTitleText text={current?.title ?? '新建线程'} animateOnMount className="w-full" style={{ fontSize: '22px', fontWeight: 700 }} />
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px', marginTop: '24px' }}>
          <button onClick={() => setRows((previous) => [{ id: `new-${Date.now()}`, title: '新建线程会话' }, ...previous])}>新增线程</button>
          <button onClick={() => setRows((previous) => previous.filter((item) => item.id !== current?.id))}>删除当前线程</button>
          <button onClick={() => setRows((previous) => previous.map((item) => item.id === current?.id ? { ...item, title: '标题更新：检查应用性能与动画效果' } : item))}>更新标题</button>
          <button onClick={() => setRows((previous) => [...previous].reverse())}>反向排序</button>
        </div>
      </section>
    </div>
  </main>;
}
if (new URLSearchParams(location.search).has('demo')) {
  syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: 360 });
  render(<Demo />, root);
} else {

try {
  syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: 160 });
  await act(async () => { render(<ListProbe />, root); });
  await act(async () => { await wait(240); });
  const oldA = row('a');
  await act(async () => { updateRows([c, a, b]); });
  await wait(90);
  const partialHeight = row('c')!.getBoundingClientRect().height;
  await wait(180);
  verify(partialHeight > 0 && partialHeight < row('c')!.getBoundingClientRect().height,
    '新增会话在真实浏览器中逐帧展开占位');
  verify(row('a') === oldA, '插入新会话保留原有条目与标题节点');
  const expandedTop = row('b')!.getBoundingClientRect().top;
  await act(async () => { updateRows([b, c, a]); });
  verify(Math.abs(row('b')!.getBoundingClientRect().top - expandedTop) < 3,
    '新增展开后重排从当前位置起步，不使用过期布局坐标');
  await act(async () => { await wait(210); });
  await act(async () => { updateRows([a, b]); });
  verify(row('c') !== null && row('c')!.inert, '删除立即禁用交互并保留退场内容');
  await wait(60);
  verify(row('c') !== null, '退场中不会提前移除条目');
  await act(async () => { updateRows([c, a, b]); });
  verify(!row('c')!.inert, '退场中重新显示恢复交互');
  await act(async () => { await wait(210); });
  await act(async () => { updateRows([a, b]); });
  await act(async () => { await wait(210); });
  verify(row('c') === null, '重新显示后再次删除仍能正确完成清理');
  const oldB = row('b');
  await act(async () => { updateRows([b, a]); });
  verify(row('b') === oldB && row('b')!.getAnimations().length > 0,
    '会话重排保留节点并播放位置过渡');
  await act(async () => { await wait(210); });
  verify(row('b')!.getBoundingClientRect().top < row('a')!.getBoundingClientRect().top,
    '重排结束后条目位置正确');
  await act(async () => { updateRows([]); });
  await act(async () => { syncRemoteDialogMotionSettings({ entrance_style: 'none', exit_style: 'none' }); });
  verify(!row('a') && !row('b'), '动画中关闭全局动效立即清理退出条目');
  verify(root.textContent?.includes('暂无会话') === true, '最后一个会话删除后显示空态');
  await act(async () => { render(null, root); });

  syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: 120 });
  await act(async () => { render(<TitleProbe />, root); });
  verify(root.querySelector('.oh-animated-title-text-enter') !== null, '会话窗口标题首次显示具有入场动效');
  await act(async () => { await wait(160); });
  await act(async () => { updateTitle('中间标题'); });
  await wait(30);
  await act(async () => { updateTitle('过期标题'); updateTitle('最新标题'); });
  verify(root.querySelector('.oh-animated-title-text-exit')?.textContent === '原始标题',
    '快速改名不会重启正在播放的标题过渡');
  verify(root.querySelector('.oh-animated-title-text')?.getAttribute('aria-label') === '最新标题',
    '动画期间无障碍名称立即反映最新标题');
  await act(async () => { await wait(160); });
  await act(async () => { await wait(160); });
  verify(root.textContent === '最新标题' && root.querySelector('.oh-animated-title-text-exit') === null,
    '标题合并更新最终收敛并释放旧文字层');
  await act(async () => { updateTitle('关闭动效后的标题'); });
  await act(async () => { syncRemoteDialogMotionSettings({ entrance_style: 'none', exit_style: 'none' }); });
  verify(root.textContent === '关闭动效后的标题', '关闭动效立即完成标题更新');
  await act(async () => { render(null, root); });
  await wait(180);
  verify(root.childElementCount === 0, '卸载后迟到的动画回调不会重新创建节点');

  syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: 360 });
  await act(async () => { render(<ComposerCollapseProbe />, root); });
  await wait(420);
  const composer = root.querySelector<HTMLElement>('.oh-session-composer')!;
  const collapseButton = root.querySelector<HTMLButtonElement>('.oh-composer-collapse-control')!;
  const expandedHeight = composer.getBoundingClientRect().height;
  const expandedWidth = composer.offsetWidth;
  await act(async () => { collapseButton.click(); });
  const collapseHeights: number[] = [];
  for (let frame = 0; frame < 28; frame++) {
    await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
    collapseHeights.push(composer.getBoundingClientRect().height);
  }
  const collapsedHeight = collapseHeights.at(-1)!;
  const largestRebound = collapseHeights.slice(1).reduce(
    (largest, height, index) => Math.max(largest, height - collapseHeights[index]!),
    0,
  );
  verify(collapseHeights[0]! > collapsedHeight + 80,
    '输入区折叠首帧保留连续布局高度，不会瞬间释放空间');
  verify(collapsedHeight < expandedHeight - 180, '输入区折叠最终收敛到紧凑高度');
  verify(largestRebound < 12, '输入区折叠期间没有明显反向回弹');
  verify(Math.abs(composer.offsetWidth - expandedWidth) < 1,
    '输入区折叠期间保持稳定宽度，避免内容重排');
  await act(async () => { render(null, root); });

  result.textContent = `通过 ${results.length} 项：\n${results.join('\n')}`;
  document.title = '线程动效回归检查通过';
} catch (error) {
  result.textContent = `检查失败：${error}`;
  document.title = '线程动效回归检查失败';
}
result.style.cssText = 'white-space:pre-wrap;padding:24px;font:14px/1.8 system-ui';

}
