import { useState } from 'preact/hooks';
import { useAnimatedLocation } from '../../../hooks/useAnimatedLocation';
import { loginWithCredentials } from '../../../api/auth';
import { ApiError, UnauthorizedError } from '../../../api/client';
import { markLoggedIn, useAuth } from '../../../state/auth';
import { t } from '../../../i18n';
import { BusyWaitDialog } from '../../../components/BusyWaitDialog';

export function LoginPage() {
  const auth = useAuth();
  const location = useAnimatedLocation();
  const [username, setUsername] = useState('openhand');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // 鉴权未开启时直接放行，避免用户被困在登录页。
  if (!auth.loading && !auth.authRequired) {
    return (
      <main class="min-h-screen flex items-center justify-center p-6">
        <section
          class="w-full max-w-md rounded-m3-xl p-8 text-center"
          style={{ backgroundColor: 'var(--m3-surface-container)', boxShadow: 'var(--m3-elev-2)' }}
        >
          <h1 class="text-xl font-semibold mb-3 oh-text-body">
            {t('login.anonymous.notice')}
          </h1>
          <button
            type="button"
            class="px-5 py-2 rounded-m3-md font-medium"
            style={{ backgroundColor: 'var(--m3-primary)', color: 'var(--m3-on-primary)', boxShadow: 'var(--m3-elev-1)' }}
            onClick={() => location.route('/threads', true)}
          >
            {t('login.anonymous.enter')}
          </button>
        </section>
      </main>
    );
  }

  const onSubmit = async (e: Event) => {
    e.preventDefault();
    if (submitting) return;
    if (!username.trim() || !password) {
      setError(t('login.error.empty'));
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const res = await loginWithCredentials(username.trim(), password);
      markLoggedIn(res.profile);
      location.route('/threads', true);
    } catch (err: unknown) {
      if (err instanceof UnauthorizedError) {
        setError(t('login.error.invalid'));
      } else if (err instanceof ApiError) {
        setError(`HTTP ${err.status}`);
      } else {
        setError(t('login.error.network'));
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main class="min-h-screen flex items-center justify-center p-6">
      <section
        class="w-full max-w-md rounded-m3-xl p-8"
        style={{ backgroundColor: 'var(--m3-surface-container)', boxShadow: 'var(--m3-elev-2)' }}
      >
        <h1 class="text-2xl font-semibold mb-1 oh-text-body">
          {t('login.title')}
        </h1>
        <p class="text-sm mb-6 oh-text-muted">
          {t('login.subtitle')}
        </p>

        <form onSubmit={onSubmit} class="flex flex-col gap-4">
          <label class="flex flex-col gap-1">
            <span class="text-xs oh-text-muted">
              {t('login.username')}
            </span>
            <input
              type="text"
              autoComplete="username"
              value={username}
              onInput={(e) => setUsername((e.target as HTMLInputElement).value)}
              class="px-3 py-2 rounded-m3-sm bg-transparent"
              style={{
                color: 'var(--m3-on-surface)',
                border: '1px solid var(--m3-outline)',
              }}
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs oh-text-muted">
              {t('login.password')}
            </span>
            <input
              type="password"
              autoComplete="current-password"
              value={password}
              onInput={(e) => setPassword((e.target as HTMLInputElement).value)}
              class="px-3 py-2 rounded-m3-sm bg-transparent"
              style={{
                color: 'var(--m3-on-surface)',
                border: '1px solid var(--m3-outline)',
              }}
            />
          </label>
          {error && (
            <div
              class="text-sm rounded-m3-sm px-3 py-2"
              style={{ color: 'var(--m3-on-primary)', backgroundColor: 'var(--m3-error)' }}
            >
              {error}
            </div>
          )}
          <button
            type="submit"
            disabled={submitting}
            class="px-5 py-2.5 rounded-m3-md font-medium mt-1 transition-opacity"
            style={{
              backgroundColor: 'var(--m3-primary)',
              color: 'var(--m3-on-primary)',
              boxShadow: 'var(--m3-elev-1)',
              opacity: submitting ? 0.6 : 1,
            }}
          >
            {submitting ? t('login.submitting') : t('login.submit')}
          </button>
        </form>
      </section>
      <BusyWaitDialog
        open={submitting}
        title={t('login.wait.title', '正在登录')}
        body={t('login.wait.body', '正在校验凭据并准备线程列表，请稍候。')}
      />
    </main>
  );
}
