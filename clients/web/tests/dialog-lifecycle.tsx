import { render } from 'preact';
import { useState } from 'preact/hooks';
import { act } from 'preact/test-utils';
import { DialogFrame } from '../src/components/DialogFrame';
import { useDialogExitMotion } from '../src/hooks/useDialogExitMotion';
import { syncRemoteDialogMotionSettings } from '../src/hooks/useDialogMotionSettings';
import { useTimeoutController } from '../src/hooks/useTimeoutController';
import { useRafScheduler } from '../src/hooks/useRafScheduler';
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
  root.textContent = `通过 ${results.length} 项：\n${results.join('\n')}`;
  root.style.whiteSpace = 'pre-wrap';
  root.style.padding = '32px';
  document.title = '弹窗回归检查通过';
} catch (error) {
  root.textContent = `检查失败：${error}`;
  document.title = '弹窗回归检查失败';
}
