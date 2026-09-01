import type { ComponentChildren, ComponentType } from 'preact';
import { lazy, Router, Route } from 'preact-iso';
import { useEffect, useState } from 'preact/hooks';
import { useAuth } from '../state/auth';
import { Appear } from '../components/Appear';
import { t } from '../i18n';
import { useAnimatedLocation } from '../hooks/useAnimatedLocation';
import { useControlledDelayedVisibility } from '../hooks/useDelayedVisibility';

const ROUTE_LOAD_TIMEOUT_MS = 15_000;
const ROUTE_LOADING_ENTER_DELAY_MS = 120;

function RouteLoadFailure() {
  return (
    <main class="min-h-screen flex items-center justify-center px-5">
      <div
        class="oh-dialog-pop-in w-full max-w-md rounded-m3-xl p-6 text-center"
        style={{
          color: 'var(--m3-on-surface)',
          background:
            'linear-gradient(135deg, var(--m3-error-container), var(--m3-surface-container-high))',
          border: '1px solid color-mix(in srgb, var(--m3-error) 35%, var(--m3-outline-variant))',
          boxShadow: 'var(--m3-elev-2)',
        }}
      >
        <p class="text-lg font-semibold">
          {t('route.loadFailed', '页面加载失败')}
        </p>
        <p class="mt-2 text-sm oh-text-muted">
          {t('route.loadFailedHint', '请检查网络连接，然后刷新重试。')}
        </p>
        <button
          type="button"
          class="mt-5 rounded-m3-md px-5 py-2.5 font-medium"
          style={{
            color: 'var(--m3-on-primary)',
            background: 'var(--m3-primary)',
            boxShadow: 'var(--m3-elev-1)',
          }}
          onClick={() => window.location.reload()}
        >
          {t('route.reload', '刷新页面')}
        </button>
      </div>
    </main>
  );
}

function lazyRoute(load: () => Promise<ComponentType>) {
  return lazy(async () => {
    let timeoutId: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<ComponentType>((resolve) => {
      timeoutId = setTimeout(() => resolve(RouteLoadFailure), ROUTE_LOAD_TIMEOUT_MS);
    });
    try {
      return await Promise.race([load(), timeout]);
    } catch {
      return RouteLoadFailure;
    } finally {
      if (timeoutId != null) clearTimeout(timeoutId);
    }
  });
}

const HomePage = lazyRoute(() =>
  import('../features/home').then((module) => module.HomePage),
);
const LoginPage = lazyRoute(() =>
  import('../features/login').then((module) => module.LoginPage),
);
const FilesPage = lazyRoute(() =>
  import('../features/files').then((module) => module.FilesPage),
);
const HarnessPage = lazyRoute(() =>
  import('../features/harness').then((module) => module.HarnessPage),
);
const LogsPage = lazyRoute(() =>
  import('../features/logs').then((module) => module.LogsPage),
);
const OpsPage = lazyRoute(() =>
  import('../features/ops').then((module) => module.OpsPage),
);
const PluginsPage = lazyRoute(() =>
  import('../features/plugins').then((module) => module.PluginsPage),
);
const SessionsPage = lazyRoute(() =>
  import('../features/sessions').then((module) => module.SessionsPage),
);
const SessionDetailPage = lazyRoute(() =>
  import('../features/sessions').then((module) => module.SessionDetailPage),
);
const SettingsPage = lazyRoute(() =>
  import('../features/settings').then((module) => module.SettingsPage),
);
const ToolboxPage = lazyRoute(() =>
  import('../features/toolbox').then((module) => module.ToolboxPage),
);

/// 鉴权守卫：service.auth_enabled=true 且无 token 时强制跳 /login。
/// 鉴权未开启或已登录则透传 children。
function RequireAuth(props: { children: ComponentChildren }) {
  const auth = useAuth();
  const location = useAnimatedLocation();
  useEffect(() => {
    if (auth.loading) return;
    if (auth.authRequired && !auth.isAuthenticated) {
      location.route('/login', true);
    }
  }, [auth.loading, auth.authRequired, auth.isAuthenticated]);

  if (auth.loading) {
    return (
      <main class="min-h-screen flex items-center justify-center">
        <p class="text-sm oh-text-muted">
          {t('guard.checking')}
        </p>
      </main>
    );
  }
  if (auth.authRequired && !auth.isAuthenticated) {
    return null;
  }
  return <>{props.children}</>;
}

function NotFound() {
  return (
    <main class="min-h-screen flex items-center justify-center">
      <div class="text-center">
        <p class="text-3xl font-semibold oh-text-body">
          404
        </p>
        <p class="text-sm mt-2 oh-text-muted">
          页面不存在
        </p>
      </div>
    </main>
  );
}

function RouteLoading({ closing }: { closing: boolean }) {
  return (
    <main
      class={`fixed inset-0 z-50 flex items-center justify-center px-5 backdrop-blur-sm ${closing ? 'oh-dialog-fade-out pointer-events-none' : 'oh-dialog-fade-in'}`}
      style={{ background: 'color-mix(in srgb, var(--m3-surface) 78%, transparent)' }}
      aria-live="polite"
      aria-busy={!closing}
      aria-hidden={closing || undefined}
    >
      <div
        class={`${closing ? 'oh-dialog-pop-out' : 'oh-dialog-pop-in'} flex w-full max-w-sm items-center gap-4 rounded-m3-xl p-5`}
        style={{
          color: 'var(--m3-on-surface)',
          background:
            'linear-gradient(135deg, var(--m3-surface-container-high), var(--m3-surface-container))',
          border: '1px solid var(--m3-outline-variant)',
          boxShadow: 'var(--m3-elev-2)',
        }}
      >
        <span
          class="oh-spin inline-flex h-11 w-11 flex-none rounded-full"
          style={{
            border: '3px solid color-mix(in srgb, var(--m3-primary) 20%, transparent)',
            borderTopColor: 'var(--m3-primary)',
          }}
          aria-hidden="true"
        />
        <div class="min-w-0">
          <p class="text-base font-semibold">
            {t('route.loading', '正在加载页面…')}
          </p>
          <p class="mt-1 text-sm oh-text-muted">
            {t('route.loadingHint', '正在准备所需功能，请稍候。')}
          </p>
        </div>
      </div>
    </main>
  );
}

function FeatureUnavailable(props: { title: string; body: string }) {
  return (
    <main class="min-h-screen flex items-center justify-center px-5">
      <div
        class="oh-appear-pop w-full max-w-[420px] rounded-m3-xl p-5 text-center"
        style={{
          background: 'var(--m3-surface-container)',
          border: '1px solid var(--m3-outline-variant)',
          boxShadow: 'var(--m3-elev-2)',
        }}
      >
        <p class="text-lg font-semibold oh-text-body">
          {props.title}
        </p>
        <p class="text-sm mt-2 oh-text-muted">
          {props.body}
        </p>
      </div>
    </main>
  );
}

function RequireServiceFeature(props: {
  feature: 'ops' | 'logs';
  children: ComponentChildren;
}) {
  const auth = useAuth();
  const enabled = props.feature === 'ops'
    ? auth.meta?.service?.ops_enabled !== false
    : auth.meta?.service?.logging_enabled !== false;
  if (enabled) return <>{props.children}</>;
  return props.feature === 'ops'
    ? <FeatureUnavailable title="运维能力未开启" body="请在 OpenHand 桌面端的消息网关配置中开启运维能力后再访问。" />
    : <FeatureUnavailable title="日志能力未开启" body="请在 OpenHand 桌面端的消息网关配置中开启日志记录后再访问。" />;
}

const HomeRoute = () => (
  <RequireAuth>
    <Appear variant="page"><HomePage /></Appear>
  </RequireAuth>
);

const LoginRoute = () => (
  <Appear variant="page"><LoginPage /></Appear>
);

const SessionsRoute = () => (
  <RequireAuth>
    <Appear variant="page"><SessionsPage /></Appear>
  </RequireAuth>
);

const SessionDetailRoute = () => (
  <RequireAuth>
    <Appear variant="page"><SessionDetailPage /></Appear>
  </RequireAuth>
);

const FilesRoute = () => (
  <RequireAuth>
    <Appear variant="page"><FilesPage /></Appear>
  </RequireAuth>
);

const ToolboxRoute = () => (
  <RequireAuth>
    <Appear variant="page"><ToolboxPage /></Appear>
  </RequireAuth>
);

const HarnessRoute = () => (
  <RequireAuth>
    <Appear variant="page"><HarnessPage /></Appear>
  </RequireAuth>
);

const SettingsRoute = () => (
  <RequireAuth>
    <Appear variant="page"><SettingsPage /></Appear>
  </RequireAuth>
);

const PluginsRoute = () => (
  <RequireAuth>
    <Appear variant="page"><PluginsPage /></Appear>
  </RequireAuth>
);

const OpsRoute = () => (
  <RequireAuth>
    <RequireServiceFeature feature="ops">
      <Appear variant="page"><OpsPage /></Appear>
    </RequireServiceFeature>
  </RequireAuth>
);

const LogsRoute = () => (
  <RequireAuth>
    <RequireServiceFeature feature="logs">
      <Appear variant="page"><LogsPage /></Appear>
    </RequireServiceFeature>
  </RequireAuth>
);

export function AppRouter() {
  const [routeLoading, setRouteLoading] = useState(false);
  const routeLoadingMotion = useControlledDelayedVisibility(routeLoading, {
    enterDelayMs: ROUTE_LOADING_ENTER_DELAY_MS,
  });
  return (
    <>
      <Router
        onLoadStart={() => setRouteLoading(true)}
        onLoadEnd={() => setRouteLoading(false)}
      >
        <Route path="/login" component={LoginRoute} />
        <Route path="/" component={HomeRoute} />
        <Route path="/threads" component={SessionsRoute} />
        <Route path="/threads/:id" component={SessionDetailRoute} />
        {/* /thread 旧路径：保持后向兼容，跳到列表 */}
        <Route path="/thread" component={SessionsRoute} />
        <Route path="/files" component={FilesRoute} />
        <Route path="/toolbox" component={ToolboxRoute} />
        <Route path="/harness" component={HarnessRoute} />
        <Route path="/settings" component={SettingsRoute} />
        <Route path="/plugins" component={PluginsRoute} />
        <Route path="/ops" component={OpsRoute} />
        <Route path="/logs" component={LogsRoute} />
        <Route default component={NotFound} />
      </Router>
      {routeLoadingMotion.visible && (
        <RouteLoading closing={routeLoadingMotion.closing} />
      )}
    </>
  );
}
