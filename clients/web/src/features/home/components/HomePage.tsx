// 首页保留只是为了让旧浏览历史 / 直链 (`/`) 不至于 404；进入即被重定向到
// 会话列表页。基于用户反馈：原有的"主题预览 + 可访问 URL"看板对终端用户毫无帮助，
// 直接让登录后的入口与 APP 端"会话列表"对齐才是正路。
import { useEffect } from 'preact/hooks';
import { useAnimatedLocation } from '../../../hooks/useAnimatedLocation';
import { t } from '../../../i18n';

export function HomePage() {
  const location = useAnimatedLocation();
  useEffect(() => {
    // 用 replace 而非 push，避免后退键又把用户拉回这个空壳。
    location.route('/threads', true);
  }, []);
  return (
    <main class="min-h-screen flex items-center justify-center">
      <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
        {t('home.redirecting', '正在跳转到会话列表…')}
      </p>
    </main>
  );
}
