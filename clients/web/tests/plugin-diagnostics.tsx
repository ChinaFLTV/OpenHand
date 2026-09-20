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
const capsule = () => root.querySelector<HTMLButtonElement>('[aria-haspopup="dialog"]')!;
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
  verify(document.activeElement === capsule(), '关闭后焦点回到诊断胶囊');
  setRemoteReducedMotion(false);
  syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: 180 });
  await act(async () => { capsule().click(); });
  await wait(250);
  await close();
  verify(document.querySelector('[role="dialog"]')?.getAttribute('data-closing') === 'true', '全局弹簧退场期间保留弹窗');
  await wait(350);
  verify(!document.querySelector('[role="dialog"]'), '退场完成后释放弹窗与滚动锁');
  verify(document.body.style.overflow !== 'hidden', '关闭后页面可以继续滚动');
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
