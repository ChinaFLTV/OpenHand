import { render } from 'preact';
import { act } from 'preact/test-utils';
import { LocationProvider } from 'preact-iso';
import { PluginsPage } from '../src/features/plugins/components/PluginsPage';
import { type PluginSummary } from '../src/api/plugins';
import { syncRemoteDialogMotionSettings } from '../src/hooks/useDialogMotionSettings';
import { setRemoteReducedMotion } from '../src/hooks/useReducedMotion';
import { applyThemeTokens, defaultThemeTokens } from '../src/theme/tokens';
import '../src/styles/global.css';

const root = document.getElementById('qa-root')!;
let copied = '';
const originalClipboard = Object.getOwnPropertyDescriptor(navigator, 'clipboard');
Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
  writeText: async (text: string) => { copied = text; },
} });
const base: PluginSummary = {
  id: 'docker', name: 'Docker', description: '容器运行环境，用于运行本地数据库服务',
  status: 'installed', enabled: true, installed_version: null, latest_version: null,
  install_path: null, dependencies: [], dependents: [], supports_uninstall: false,
  error_message: null, has_update: false, diagnostics: [],
};
let current = base;
const results: string[] = [];
const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const verify = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
  results.push(message);
};
window.fetch = async (input) => String(input).startsWith('/api/plugins')
  ? Response.json({ items: [current, { ...base, id: 'python', name: 'Python' }] })
  : Response.json({ service: { auth_enabled: false }, preferences: { reduce_motion: true, locale: 'zh' } });
const refresh = async () => {
  const rescan = [...root.querySelectorAll('button')].find((button) => button.textContent === '重新扫描')!;
  await act(async () => { rescan.click(); await wait(30); });
  await wait(250);
};
const capsule = () => root.querySelector<HTMLButtonElement>('.oh-plugin-diagnostic-slot:not([inert]) button')!;
const motion = () => root.querySelector<HTMLElement>('.oh-plugin-diagnostic-motion')!;
const close = async () => {
  await act(async () => {
    document.querySelector<HTMLButtonElement>('[role="dialog"] button[aria-label="关闭"]')!.click();
  });
};
applyThemeTokens(defaultThemeTokens);
setRemoteReducedMotion(true);
try {
  await act(async () => { render(<LocationProvider><PluginsPage /></LocationProvider>, root); await wait(100); });
  await wait(600);
  const position = () => [...root.querySelectorAll('li')].map((item) => {
    const { y, height } = item.getBoundingClientRect();
    return [y, height];
  });
  verify(position().length === 2, '插件列表完成加载');
  verify(capsule() == null, '初始零诊断不显示胶囊');
  const baseline = JSON.stringify(position());
  current = { ...base, diagnostics: [
    { severity: 'error', message: '错误正文'.repeat(1000) },
    { severity: 'warning', message: '无法获取远端版本，请稍后重试。' },
  ] };
  await refresh();
  verify(JSON.stringify(position()) === baseline, '诊断消息增多或变长不改变卡片高度及后续卡片位置');
  verify(!root.textContent?.includes('错误正文'), '卡片内不展示诊断正文');
  await act(async () => { capsule().focus(); capsule().click(); });
  verify(document.querySelector('[role="dialog"]')?.textContent?.includes('错误正文'.repeat(1000)) === true, '弹窗保留完整长消息');
  verify(document.documentElement.scrollWidth <= innerWidth, '长消息不会造成横向溢出');
  await act(async () => {
    [...document.querySelectorAll<HTMLButtonElement>('[role="dialog"] button')]
      .find((button) => button.textContent === '复制全部消息')!.click();
    await wait(20);
  });
  verify(copied.includes('错误正文'.repeat(1000)) && copied.includes('无法获取远端版本'), '复制全部保留完整错误与警告');
  await act(async () => {
    [...document.querySelectorAll<HTMLButtonElement>('[role="dialog"] button')]
      .find((button) => button.textContent === '复制')!.click();
    await wait(20);
  });
  verify(copied === '错误正文'.repeat(1000), '单条复制仅包含当前消息');
  current = { ...base, diagnostics: [{ severity: 'warning', message: '最新警告' }] };
  await refresh();
  verify(document.querySelector('[role="dialog"]')?.textContent?.includes('最新警告') === true, '打开中的弹窗随数据刷新');
  current = base;
  await refresh();
  verify(document.querySelector('[role="dialog"]')?.textContent?.includes('当前没有错误或警告') === true, '消息消失后显示空态，不保留旧错误');
  await close();
  await wait(20);
  verify(!document.querySelector('[role="dialog"]'), '减少动态效果时立即退出');
  verify(capsule() == null && getComputedStyle(motion()).visibility === 'hidden', '清空诊断后胶囊隐藏并退出焦点与读屏');
  current = { ...base, diagnostics: [{ severity: 'warning', message: '新的警告' }] };
  await refresh();
  await act(async () => { capsule().focus(); capsule().click(); });
  await close();
  await wait(20);
  verify(document.activeElement === capsule(), '诊断仍存在时关闭弹窗恢复焦点');
  setRemoteReducedMotion(false);
  syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: 180 });
  await act(async () => { capsule().click(); });
  await wait(250);
  await close();
  verify(document.querySelector('[role="dialog"]')?.getAttribute('data-closing') === 'true', '全局弹簧退场期间保留弹窗');
  await wait(350);
  verify(!document.querySelector('[role="dialog"]'), '退场完成后释放弹窗与滚动锁');
  verify(document.body.style.overflow !== 'hidden', '关闭后页面可以继续滚动');
  // 延长动画以检查中间帧和快速反向，避免只验证最终状态。
  syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: 1000 });
  current = base;
  await refresh();
  const exitOpacity = Number(getComputedStyle(motion()).opacity);
  verify(exitOpacity > 0 && exitOpacity < 1 && capsule() == null, '退场具有中间帧且立即禁止交互');
  verify(!root.textContent?.includes('诊断 0'), '退场保留原数量，不闪现零诊断');
  current = { ...base, diagnostics: [{ severity: 'error', message: '快速恢复的错误' }] };
  await refresh();
  verify(Number(getComputedStyle(motion()).opacity) > 0 && capsule() != null, '退场中恢复诊断可自然反向');
  await wait(1100);
  verify(getComputedStyle(motion()).opacity === '1', '快速反向后胶囊正常可见');
  current = base;
  await refresh();
  await wait(1100);
  verify(getComputedStyle(motion()).visibility === 'hidden' && capsule() == null, '退场结束后胶囊完全隐藏');
  verify(JSON.stringify(position()) === baseline, '完整显隐后卡片布局保持稳定');
  current = { ...base, diagnostics: [{ severity: 'warning', message: '再次出现' }] };
  await refresh();
  const enterOpacity = Number(getComputedStyle(motion()).opacity);
  verify(enterOpacity > 0 && enterOpacity < 1, '隐藏后重新出现具有进场中间帧');
  current = base;
  await refresh();
  await act(async () => { setRemoteReducedMotion(true); });
  await wait(30);
  verify(getComputedStyle(motion()).visibility === 'hidden', '退场中开启减少动态效果立即隐藏');
  setRemoteReducedMotion(false);
  syncRemoteDialogMotionSettings({ entrance_style: 'none', exit_style: 'none', duration_ms: 180 });
  current = { ...base, diagnostics: [{ severity: 'error', message: '禁用动效检查' }] };
  await refresh();
  verify(getComputedStyle(motion()).opacity === '1', '禁用动效时立即显示胶囊');
  current = base;
  await refresh();
  verify(getComputedStyle(motion()).visibility === 'hidden', '禁用动效时立即隐藏胶囊');
  syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: 180 });
  current = { ...base, diagnostics: [
    { severity: 'error', message: 'Docker CLI 可用，但 Docker daemon 未运行或不可访问。' },
    { severity: 'warning', message: '暂时无法检查远端镜像版本，请稍后重试。' },
  ] };
  await refresh();
  const report = document.createElement('pre');
  report.id = 'qa-results';
  report.style.cssText = 'padding:20px;white-space:pre-wrap';
  report.textContent = `全部通过（${results.length} 项）\n${results.join('\n')}`;
  document.body.append(report);
} catch (error) {
  const report = document.createElement('pre');
  report.id = 'qa-results';
  report.textContent = `检查失败：${String(error)}\n${results.join('\n')}`;
  document.body.append(report);
}
 finally {
  if (originalClipboard) Object.defineProperty(navigator, 'clipboard', originalClipboard);
  else Reflect.deleteProperty(navigator, 'clipboard');
}
