import { render } from 'preact';
import { App } from './app';
import { t } from './i18n';
import { initReducedMotionAttribute } from './hooks/useReducedMotion';
import { registerServiceWorker } from './services/pwa';
import './styles/global.css';

// 首屏前同步 OS / localStorage 的 reduce-motion 偏好到 <html data-motion>，
// 避免 useEffect 触发前的一帧动画闪烁。
initReducedMotionAttribute();

// PWA Service Worker 注册 (生产环境). 失败完全静默, 不影响主流程。
registerServiceWorker();

const root = document.getElementById('root');
if (!root) {
  throw new Error(t('boot.missingMount'));
}
render(<App />, root);
