import { useState } from 'preact/hooks';
import { logout, useAuth } from '../state/auth';
import { useLocation } from 'preact-iso';
import { setLang, t, useLang } from '../i18n';

export function HomePage() {
  const auth = useAuth();
  const location = useLocation();
  const lang = useLang();
  const [copied, setCopied] = useState<string | null>(null);

  const urls = auth.meta?.service?.accessible_urls ?? [];
  const boundUrl = auth.meta?.service?.bound_url ?? '';
  const profile = auth.profile;

  const onCopy = async (url: string) => {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(url);
      setTimeout(() => setCopied((cur) => (cur === url ? null : cur)), 1400);
    } catch {
      // 老旧浏览器无 clipboard API：fallback 选中文本
      const span = document.createElement('span');
      span.textContent = url;
      document.body.appendChild(span);
      const range = document.createRange();
      range.selectNode(span);
      window.getSelection()?.removeAllRanges();
      window.getSelection()?.addRange(range);
      document.execCommand('copy');
      document.body.removeChild(span);
      setCopied(url);
      setTimeout(() => setCopied((cur) => (cur === url ? null : cur)), 1400);
    }
  };

  const onLogout = () => {
    logout();
    if (auth.authRequired) location.route('/login');
  };

  return (
    <main class="min-h-screen flex items-start justify-center p-6 sm:p-12">
      <section
        class="w-full max-w-3xl rounded-m3-xl p-8 sm:p-12"
        style={{
          backgroundColor: 'var(--m3-surface-container)',
          boxShadow: 'var(--m3-elev-2)',
        }}
      >
        <header class="flex items-start justify-between gap-4 mb-6">
          <div>
            <h1
              class="text-3xl sm:text-4xl font-semibold tracking-tight"
              style={{ color: 'var(--m3-on-surface)' }}
            >
              {t('app.brand')}
            </h1>
            <p class="text-sm mt-1" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {t('home.subtitle')}
            </p>
          </div>
          <div class="flex items-center gap-2 flex-wrap justify-end">
            <div
              role="group"
              aria-label={t('common.lang.label')}
              class="inline-flex rounded-m3-sm overflow-hidden"
              style={{ border: '1px solid var(--m3-outline)' }}
            >
              {(['zh', 'en'] as const).map((opt) => {
                const active = lang === opt;
                return (
                  <button
                    key={opt}
                    type="button"
                    onClick={() => setLang(opt)}
                    class="text-xs px-2.5 py-1.5 transition-colors"
                    style={{
                      color: active ? 'var(--m3-on-primary)' : 'var(--m3-on-surface-variant)',
                      backgroundColor: active ? 'var(--m3-primary)' : 'transparent',
                      minWidth: '36px',
                      cursor: active ? 'default' : 'pointer',
                    }}
                    aria-pressed={active}
                    title={t('common.lang.label')}
                  >
                    {opt === 'zh' ? t('common.lang.zh') : t('common.lang.en')}
                  </button>
                );
              })}
            </div>
            <button
              type="button"
              onClick={() => location.route('/threads')}
              class="text-sm px-3 py-1.5 rounded-m3-sm transition-colors"
              style={{
                color: 'var(--m3-on-primary)',
                backgroundColor: 'var(--m3-primary)',
                boxShadow: 'var(--m3-elev-1)',
              }}
            >
              {t('home.openSessions', '进入会话列表')}
            </button>
            <button
              type="button"
              onClick={() => location.route('/files')}
              class="text-sm px-3 py-1.5 rounded-m3-sm transition-colors"
              style={{
                color: 'var(--m3-on-surface)',
                border: '1px solid var(--m3-outline)',
                backgroundColor: 'transparent',
              }}
            >
              {t('home.openFiles', '工作区文件')}
            </button>
            <button
              type="button"
              onClick={() => location.route('/ops')}
              class="text-sm px-3 py-1.5 rounded-m3-sm transition-colors"
              style={{
                color: 'var(--m3-on-surface)',
                border: '1px solid var(--m3-outline)',
                backgroundColor: 'transparent',
              }}
            >
              {t('home.openOps', 'Ops')}
            </button>
            <button
              type="button"
              onClick={() => location.route('/logs')}
              class="text-sm px-3 py-1.5 rounded-m3-sm transition-colors"
              style={{
                color: 'var(--m3-on-surface)',
                border: '1px solid var(--m3-outline)',
                backgroundColor: 'transparent',
              }}
            >
              {t('home.openLogs', '日志')}
            </button>
            {auth.authRequired && (
              <button
                type="button"
                onClick={onLogout}
                class="text-sm px-3 py-1.5 rounded-m3-sm transition-colors"
                style={{
                  color: 'var(--m3-on-surface-variant)',
                  border: '1px solid var(--m3-outline)',
                  backgroundColor: 'transparent',
                }}
              >
                {t('common.logout')}
              </button>
            )}
          </div>
        </header>

        {profile?.username && (
          <div
            class="rounded-m3-sm px-4 py-2 text-sm mb-6"
            style={{ backgroundColor: 'var(--m3-surface)', color: 'var(--m3-on-surface-variant)' }}
          >
            {t('home.profile.label')}<b style={{ color: 'var(--m3-on-surface)' }}>{profile.username}</b>
            {profile.device_name ? ` · ${profile.device_name}` : ''}
          </div>
        )}

        <div
          class="rounded-m3-md p-5 mb-6"
          style={{
            backgroundColor: 'var(--m3-surface)',
            border: '1px solid var(--m3-outline)',
          }}
        >
          <div class="flex items-center gap-2 mb-3">
            <span
              class="inline-block w-2.5 h-2.5 rounded-full"
              style={{ backgroundColor: auth.themeSource === 'api' ? 'var(--m3-primary)' : 'var(--m3-outline)' }}
            />
            <span class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {auth.themeSource === 'api' ? t('home.theme.source.api') : t('home.theme.source.default')}
              {auth.error ? ` · ${auth.error}` : ''}
            </span>
          </div>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {(
              [
                ['primary', auth.themeTokens.primary],
                ['surface', auth.themeTokens.surface],
                ['surfaceContainer', auth.themeTokens.surfaceContainer],
                ['outline', auth.themeTokens.outline],
              ] as const
            ).map(([name, color]) => (
              <div key={name} class="flex flex-col gap-1">
                <div
                  class="h-12 rounded-m3-sm"
                  style={{ backgroundColor: color, border: '1px solid var(--m3-outline)' }}
                />
                <span class="text-xs font-mono" style={{ color: 'var(--m3-on-surface-variant)' }}>
                  {name}
                </span>
                <span class="text-xs font-mono" style={{ color: 'var(--m3-on-surface)' }}>
                  {color}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div
          class="rounded-m3-md p-5"
          style={{
            backgroundColor: 'var(--m3-surface)',
            border: '1px solid var(--m3-outline)',
          }}
        >
          <h2 class="text-lg font-semibold mb-3" style={{ color: 'var(--m3-on-surface)' }}>
            {t('home.urls.title')}
          </h2>
          {urls.length === 0 ? (
            <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
              {auth.meta ? t('home.urls.empty') : t('common.loading')}
            </p>
          ) : (
            <ul class="flex flex-wrap gap-2">
              {urls.map((url) => (
                <li key={url}>
                  <button
                    type="button"
                    onClick={() => void onCopy(url)}
                    class="px-3 py-1.5 rounded-m3-sm text-sm font-mono transition-colors"
                    style={{
                      backgroundColor: copied === url ? 'var(--m3-on-primary)' : 'var(--m3-primary)',
                      color: copied === url ? 'var(--m3-primary)' : 'var(--m3-on-primary)',
                      boxShadow: 'var(--m3-elev-1)',
                      border: copied === url ? '1px solid var(--m3-primary)' : 'none',
                    }}
                    title={url === boundUrl ? t('home.urls.boundHint') : t('home.urls.lanHint')}
                  >
                    {url}
                    {copied === url ? `  ✓ ${t('common.copied')}` : ''}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <p class="mt-6 text-xs" style={{ color: 'var(--m3-on-surface-variant)' }}>
          {t('home.next.stages')}
        </p>
      </section>
    </main>
  );
}
