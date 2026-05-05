import type { ComponentChildren } from 'preact';
import { LocationProvider, Router, Route, useLocation } from 'preact-iso';
import { useEffect } from 'preact/hooks';
import { useAuth } from './state/auth';
import { HomePage } from './pages/HomePage';
import { LoginPage } from './pages/LoginPage';
import { SessionsPage } from './pages/SessionsPage';
import { SessionDetailPage } from './pages/SessionDetailPage';
import { FilesPage } from './pages/FilesPage';
import { OpsPage } from './pages/OpsPage';
import { LogsPage } from './pages/LogsPage';
import { Appear } from './components/Appear';
import { t } from './i18n';

/// 鉴权守卫：service.auth_enabled=true 且无 token 时强制跳 /login。
/// 鉴权未开启或已登录则透传 children。
function RequireAuth(props: { children: ComponentChildren }) {
  const auth = useAuth();
  const location = useLocation();
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

const HomeRoute = () => (
  <RequireAuth>
    <Appear variant="page"><HomePage /></Appear>
  </RequireAuth>
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

const OpsRoute = () => (
  <RequireAuth>
    <Appear variant="page"><OpsPage /></Appear>
  </RequireAuth>
);

const LogsRoute = () => (
  <RequireAuth>
    <Appear variant="page"><LogsPage /></Appear>
  </RequireAuth>
);

export function App() {
  return (
    <LocationProvider>
      <Router>
        <Route path="/login" component={LoginPage} />
        <Route path="/" component={HomeRoute} />
        <Route path="/threads" component={SessionsRoute} />
        <Route path="/threads/:id" component={SessionDetailRoute} />
        {/* /thread 旧路径：保持后向兼容，跳到列表 */}
        <Route path="/thread" component={SessionsRoute} />
        <Route path="/files" component={FilesRoute} />
        <Route path="/ops" component={OpsRoute} />
        <Route path="/logs" component={LogsRoute} />
        <Route default component={NotFound} />
      </Router>
    </LocationProvider>
  );
}
