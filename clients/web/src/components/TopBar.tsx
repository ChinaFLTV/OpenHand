import type { ComponentChildren } from 'preact';
import { useState } from 'preact/hooks';
import { logout, useAuth } from '../state/auth';
import { t } from '../i18n';
import { ConfirmDialog } from './ConfirmDialog';
import { showSnackbar } from './Snackbar';
import { useAnimatedLocation } from '../hooks/useAnimatedLocation';

interface TopBarProps {
  /// 主标题；缺省 → 走 i18n `app.brand`
  title?: string;
  /// 副标题；缺省 → 走 i18n `home.subtitle`
  subtitle?: string;
  /// 紧凑模式：减小 padding/字号，用于详情页等
  compact?: boolean;
  /// 标题左侧右侧扩展槽（可选，例如详情页放"返回会话列表"）
  leadingSlot?: ComponentChildren;
  /// 标题右侧操作槽（可选，例如线程列表页放浏览器全屏按钮）。
  actionSlot?: ComponentChildren;
  /// 隐藏右侧登出入口。
  hideNav?: boolean;
}

export function TopBar(props: TopBarProps) {
  const { compact = false, hideNav = false, title, subtitle, leadingSlot, actionSlot } = props;
  const auth = useAuth();
  const location = useAnimatedLocation();
  const [logoutConfirmOpen, setLogoutConfirmOpen] = useState(false);

  const confirmLogout = () => {
    setLogoutConfirmOpen(false);
    logout();
    showSnackbar(t('common.logout.ok', '已退出登录'), { tone: 'success' });
    if (auth.authRequired) location.route('/login', true);
  };

  const navBtnClass = `oh-tap-press text-sm rounded-m3-sm transition-colors ${
    compact ? 'px-2.5 py-1' : 'px-3 py-1.5'
  }`;

  return (
    <>
      <header
        class={`oh-topbar flex items-start justify-between gap-4 flex-wrap ${compact ? 'is-compact mb-4' : 'mb-6'}`}
      >
      <div class="flex items-center gap-3 min-w-0">
        {leadingSlot}
        <span class="oh-topbar-logo-wrap" aria-hidden="true">
          <img
            src="./openhand_logo.png"
            alt=""
            width={compact ? 34 : 46}
            height={compact ? 34 : 46}
            decoding="async"
            loading="eager"
            class="oh-topbar-logo"
          />
        </span>
        <div class="min-w-0">
          <h1
            class={`oh-topbar-title font-semibold tracking-tight truncate ${
              compact ? 'text-lg' : 'text-2xl sm:text-3xl'
            }`}
          >
            {title ?? t('app.brand')}
          </h1>
          {subtitle !== '' ? (
            <p
              class={`oh-topbar-subtitle mt-0.5 truncate ${compact ? 'text-xs' : 'text-sm'}`}
            >
              {subtitle ?? t('home.subtitle')}
            </p>
          ) : null}
        </div>
      </div>

      <div class="flex items-center gap-2 flex-wrap justify-end">
        {actionSlot}
        {!hideNav && auth.authRequired ? (
          <button
            type="button"
            onClick={() => setLogoutConfirmOpen(true)}
            class={`${navBtnClass} oh-topbar-action`}
          >
            {t('common.logout')}
          </button>
        ) : null}
      </div>
      </header>
      {logoutConfirmOpen ? (
        <ConfirmDialog
          title={t('common.logout.confirmTitle', '退出登录?')}
          body={t('common.logout.confirmBody', '退出后需要重新登录才能访问 Web 消息服务。')}
          confirmLabel={t('common.logout', '退出登录')}
          cancelLabel={t('common.cancel', '取消')}
          danger
          onCancel={() => setLogoutConfirmOpen(false)}
          onConfirm={confirmLogout}
        />
      ) : null}
    </>
  );
}
