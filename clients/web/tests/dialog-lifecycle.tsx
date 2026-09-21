import { render } from 'preact';
import { useState } from 'preact/hooks';
import { act } from 'preact/test-utils';
import { DialogFrame } from '../src/components/DialogFrame';
import { MenuSelect } from '../src/components/MenuSelect';
import { useDialogExitMotion } from '../src/hooks/useDialogExitMotion';
import { syncRemoteDialogMotionSettings } from '../src/hooks/useDialogMotionSettings';
import { useTimeoutController } from '../src/hooks/useTimeoutController';
import { useRafScheduler } from '../src/hooks/useRafScheduler';
import { setRemoteReducedMotion } from '../src/hooks/useReducedMotion';
import { useControlledDelayedVisibility, useDelayedVisibility } from '../src/hooks/useDelayedVisibility';
import { LocationProvider } from 'preact-iso';
import { useAnimatedLocation } from '../src/hooks/useAnimatedLocation';
import '../src/styles/global.css';

const root = document.getElementById('qa-root')!;
const results: string[] = [];
function verify(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
  results.push(message);
}
const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
let changeDialogs!: (value: { parent: boolean; child: boolean }) => void;
function FocusProbe() {
  const [dialogs, setDialogs] = useState({ parent: false, child: false });
  changeDialogs = setDialogs;
  return <>
    <button id="outside">打开弹窗</button>
    {dialogs.parent && <DialogFrame closing={false} ariaLabel="父弹窗">
      <div hidden><button id="hidden">隐藏按钮</button></div>
      <button id="first">首个操作</button>
      <button id="last">最后操作</button>
    </DialogFrame>}
    {dialogs.child && <DialogFrame closing={false} ariaLabel="子弹窗"><button id="child">子弹窗操作</button></DialogFrame>}
  </>;
}
let requestClose!: () => void;
let beforeCloses = 0;
let closes = 0;
function MotionProbe() {
  const motion = useDialogExitMotion(() => { closes += 1; }, {
    onBeforeClose: () => {
      beforeCloses += 1;
      if (beforeCloses < 2) requestClose();
    },
  });
  requestClose = motion.requestClose;
  return <DialogFrame closing={motion.closing} ariaLabel="动画弹窗"><button>确认</button></DialogFrame>;
}
let timer!: ReturnType<typeof useTimeoutController>;
let frame!: ReturnType<typeof useRafScheduler>;
let timerCalls = 0;
let frameCalls = 0;
function SchedulerProbe() {
  timer = useTimeoutController();
  frame = useRafScheduler(() => frameCalls++);
  return null;
}
let visibility!: ReturnType<typeof useDelayedVisibility>;
let setControlledOpen!: (open: boolean) => void;
let controlled!: ReturnType<typeof useControlledDelayedVisibility>;
function VisibilityProbe() {
  visibility = useDelayedVisibility();
  const [open, setOpen] = useState(false);
  setControlledOpen = setOpen;
  controlled = useControlledDelayedVisibility(open, { enterDelayMs: 80 });
  return null;
}
let route!: ReturnType<typeof useAnimatedLocation>['route'];
function RouteProbe() {
  route = useAnimatedLocation().route;
  return null;
}
try {
  await act(async () => { render(<FocusProbe />, root); });
  document.getElementById('outside')!.focus();
  await act(async () => { changeDialogs({ parent: true, child: false }); });
  await wait(0);
  verify(document.activeElement?.id === 'first', '隐藏祖先内的按钮不会抢占弹窗焦点');
  document.getElementById('last')!.focus();
  window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }));
  verify(document.activeElement?.id === 'first', 'Tab 从末尾自然回到首个可用操作');
  await act(async () => { changeDialogs({ parent: true, child: true }); });
  await wait(0);
  verify(document.activeElement?.id === 'child', '嵌套弹窗取得焦点');
  await act(async () => { changeDialogs({ parent: false, child: true }); });
  verify(document.body.style.overflow === 'hidden', '移除底层弹窗时保留滚动锁');
  await act(async () => { changeDialogs({ parent: false, child: false }); });
  verify(document.activeElement?.id === 'outside', '乱序卸载嵌套弹窗后恢复原始触发按钮');
  verify(document.body.style.overflow !== 'hidden', '最后一个弹窗关闭后释放滚动锁');

  let parentCloses = 0;
  syncRemoteDialogMotionSettings({ exit_style: 'spring_scale', duration_ms: 360 });
  await act(async () => render(<DialogFrame closing={false} ariaLabel="菜单父弹窗" onRequestClose={() => parentCloses++}>
    <MenuSelect options={[{ value: 'current', label: '当前选项' }]} value="current" onChange={() => {}} />
  </DialogFrame>, root));
  const menuTrigger = root.querySelector<HTMLButtonElement>('button[aria-haspopup="listbox"]')
    ?? document.querySelector<HTMLButtonElement>('button[aria-haspopup="listbox"]')!;
  await act(async () => menuTrigger.click());
  verify(document.querySelector('[role="listbox"]') != null, '真实下拉菜单正常挂载');
  const escape = () => window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
  await act(async () => { escape(); });
  verify(document.querySelector('[role="listbox"]') != null, '下拉菜单关闭时保留全局退场动画');
  await act(async () => { escape(); });
  verify(parentCloses === 0, '下拉菜单退场时再次按 Escape 不关闭父弹窗');
  await act(async () => { await wait(400); });
  verify(document.querySelector('[role="listbox"]') == null, '全局退场结束后移除下拉菜单');
  await act(async () => { escape(); });
  verify(parentCloses === 1, '菜单退场结束后恢复父弹窗的关闭操作');
  await act(async () => { render(null, root); });

  syncRemoteDialogMotionSettings({ exit_style: 'spring_scale', duration_ms: 120 });
  await act(async () => { render(<MotionProbe />, root); });
  await act(async () => { requestClose(); });
  verify(beforeCloses === 1, '关闭前回调同步重入时仅执行一次');
  verify(closes === 0, '全局弹簧退场完成前保留弹窗');
  await act(async () => { await wait(160); });
  verify(closes === 1, '全局退场时长结束后只关闭一次');
  await act(async () => { render(null, root); });

  syncRemoteDialogMotionSettings({ exit_style: 'none', duration_ms: 120 });
  await act(async () => { render(<MotionProbe />, root); });
  await act(async () => { requestClose(); });
  verify(closes === 2, '关闭动效禁用时立即完成退出');
  await act(async () => { render(null, root); });

  syncRemoteDialogMotionSettings({ exit_style: 'spring_scale', duration_ms: 600 });
  await act(async () => { render(<MotionProbe />, root); });
  await act(async () => { requestClose(); });
  await act(async () => { syncRemoteDialogMotionSettings({ exit_style: 'none' }); });
  verify(closes === 3, '退场中禁用全局动画立即完成关闭');
  await act(async () => { setRemoteReducedMotion(true); });
  verify(closes === 3, '关闭完成后再次修改动效设置不会重复回调');
  await act(async () => { render(null, root); });
  setRemoteReducedMotion(false);

  syncRemoteDialogMotionSettings({ exit_style: 'spring_scale', duration_ms: 600 });
  await act(async () => { render(<MotionProbe />, root); });
  await act(async () => { requestClose(); });
  await act(async () => { setRemoteReducedMotion(true); });
  verify(closes === 4, '退场中开启减少动态效果立即完成关闭');
  await act(async () => { render(null, root); });
  setRemoteReducedMotion(false);

  syncRemoteDialogMotionSettings({ exit_style: 'spring_scale', duration_ms: 120 });
  await act(async () => { render(<MotionProbe />, root); });
  await act(async () => { requestClose(); });
  await act(async () => { syncRemoteDialogMotionSettings({ exit_style: 'spring_scale', duration_ms: 600 }); });
  await act(async () => { await wait(160); });
  verify(closes === 4, '退场中延长全局时长不会按旧时限提前移除弹窗');
  await act(async () => { syncRemoteDialogMotionSettings({ exit_style: 'spring_scale', duration_ms: 120 }); });
  verify(closes === 5, '缩短退场时长会扣除已播放时间，不重新等待完整时长');
  await act(async () => { render(null, root); });

  syncRemoteDialogMotionSettings({ exit_style: 'spring_scale', duration_ms: 120 });
  await act(async () => { render(<VisibilityProbe />, root); });
  await act(async () => { visibility.show(); visibility.hide(); visibility.show(); });
  await act(async () => { await wait(160); });
  verify(visibility.visible && !visibility.closing, '浮层重新打开后旧退场计时器不会将其关闭');
  await act(async () => { visibility.hide(); });
  await act(async () => { syncRemoteDialogMotionSettings({ exit_style: 'none' }); });
  verify(!visibility.visible, '通用浮层复用全局即时关闭行为');
  await act(async () => { setControlledOpen(true); });
  verify(!controlled.visible, '受控浮层遵守进场延迟');
  await act(async () => { setControlledOpen(false); });
  await act(async () => { await wait(120); });
  verify(!controlled.visible, '进场前取消不会留下迟到浮层');
  await act(async () => { setControlledOpen(true); });
  await act(async () => { await wait(120); });
  verify(controlled.visible, '延迟结束后受控浮层正常显示');
  await act(async () => { syncRemoteDialogMotionSettings({ exit_style: 'spring_scale', duration_ms: 120 }); });
  await act(async () => { setControlledOpen(false); });
  verify(controlled.closing, '受控浮层保留退场阶段');
  await act(async () => { setControlledOpen(true); });
  verify(controlled.visible && !controlled.closing, '退场期间重新打开立即恢复，不再等待进场延迟');
  await act(async () => { render(null, root); });

  await act(async () => { render(<SchedulerProbe />, root); });
  timer.scheduleTimer(() => timerCalls++, 1000);
  frame.schedule();
  await act(async () => { render(null, root); });
  timer.scheduleTimer(() => timerCalls++, 0);
  frame.schedule();
  frame.flush();
  await wait(30);
  verify(timerCalls === 0, '组件卸载后取消计时器并拒绝迟到的调度');
  verify(frameCalls === 0, '组件卸载后取消动画帧并拒绝迟到的刷新');

  const originalTransition = Object.getOwnPropertyDescriptor(document, 'startViewTransition');
  const updates: Array<() => void> = [];
  Object.defineProperty(document, 'startViewTransition', {
    configurable: true,
    value: (update: () => void) => {
      updates.push(update);
      return { finished: Promise.resolve() };
    },
  });
  try {
    await act(async () => { render(<LocationProvider><RouteProbe /></LocationProvider>, root); });
    route('/tests/dialog-lifecycle.html?route=old');
    route('/tests/dialog-lifecycle.html?route=new');
    await act(async () => { updates[1](); updates[0](); });
    verify(location.search === '?route=new', '连续导航时迟到的旧过渡不能覆盖最新路由');
    await act(async () => { render(null, root); });
  } finally {
    if (originalTransition) Object.defineProperty(document, 'startViewTransition', originalTransition);
    else Reflect.deleteProperty(document, 'startViewTransition');
    history.replaceState(null, '', '/tests/dialog-lifecycle.html');
  }
  root.textContent = `通过 ${results.length} 项：\n${results.join('\n')}`;
  root.style.whiteSpace = 'pre-wrap';
  root.style.padding = '32px';
  document.title = '弹窗回归检查通过';
} catch (error) {
  root.textContent = `检查失败：${error}`;
  document.title = '弹窗回归检查失败';
}
