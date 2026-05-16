import type { ComponentChildren } from 'preact';
import { Router, Route } from 'preact-iso';
import { useEffect } from 'preact/hooks';
import { useAuth } from '../state/auth';
import { HomePage } from '../pages/HomePage';
import { LoginPage } from '../pages/LoginPage';
import { SessionsPage } from '../pages/SessionsPage';
import { SessionDetailPage } from '../pages/SessionDetailPage';
import { FilesPage } from '../pages/FilesPage';
import { OpsPage } from '../pages/OpsPage';
import { LogsPage } from '../pages/LogsPage';
import { ToolboxPage } from '../pages/ToolboxPage';
import { HardnessPage } from '../pages/HardnessPage';
import { SettingsPage } from '../pages/SettingsPage';
import { PluginsPage } from '../pages/PluginsPage';
import { Appear } from '../components/Appear';
import { t } from '../i18n';
import { useAnimatedLocation } from '../hooks/useAnimatedLocation';

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
        <p class="text-sm" style={{ color: 'var(--m3-on-surface-variant)' }}>
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
        <p class="text-3xl font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
          404
        </p>
        <p class="text-sm mt-2" style={{ color: 'var(--m3-on-surface-variant)' }}>
          页面不存在
        </p>
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
        <p class="text-lg font-semibold" style={{ color: 'var(--m3-on-surface)' }}>
          {props.title}
        </p>
        <p class="text-sm mt-2" style={{ color: 'var(--m3-on-surface-variant)' }}>
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

const HardnessRoute = () => (
  <RequireAuth>
    <Appear variant="page"><HardnessPage /></Appear>
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
  return (
    <Router>
      <Route path="/login" component={LoginRoute} />
      <Route path="/" component={HomeRoute} />
      <Route path="/threads" component={SessionsRoute} />
      <Route path="/threads/:id" component={SessionDetailRoute} />
      {/* /thread 旧路径：保持后向兼容，跳到列表 */}
      <Route path="/thread" component={SessionsRoute} />
      <Route path="/files" component={FilesRoute} />
      <Route path="/toolbox" component={ToolboxRoute} />
      <Route path="/hardness" component={HardnessRoute} />
      <Route path="/settings" component={SettingsRoute} />
      <Route path="/plugins" component={PluginsRoute} />
      <Route path="/ops" component={OpsRoute} />
      <Route path="/logs" component={LogsRoute} />
      <Route default component={NotFound} />
    </Router>
  );
}
