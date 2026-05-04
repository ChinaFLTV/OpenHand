import { useEffect, useState } from 'preact/hooks';
import { fetchApiMeta, metaThemeToTokens, type ApiMetaResponse } from './api/meta';
import { applyThemeTokens, defaultThemeTokens, type M3ThemeTokens } from './theme/tokens';

interface ThemeState {
  tokens: M3ThemeTokens;
  source: 'default' | 'api';
  error?: string;
}

export function App() {
  const [meta, setMeta] = useState<ApiMetaResponse | null>(null);
  const [theme, setTheme] = useState<ThemeState>({
    tokens: defaultThemeTokens,
    source: 'default',
  });

  // 启动后立即拉一次 /api/meta，把 OpenHand 当前主题色覆盖进 :root。
  // 失败保留默认 token，仅记录错误用于调试。
  useEffect(() => {
    const ctrl = new AbortController();
    fetchApiMeta(ctrl.signal)
      .then((res) => {
        setMeta(res);
        const tokens = metaThemeToTokens(res.theme, defaultThemeTokens);
        applyThemeTokens(tokens);
        setTheme({ tokens, source: 'api' });
      })
      .catch((err: unknown) => {
        if (ctrl.signal.aborted) return;
        const msg = err instanceof Error ? err.message : String(err);
        setTheme((prev) => ({ ...prev, error: msg }));
      });
    return () => ctrl.abort();
  }, []);

  const urls = meta?.service?.accessible_urls ?? [];
  const boundUrl = meta?.service?.bound_url ?? '';

  return (
    <main class="min-h-screen flex items-start justify-center p-6 sm:p-12">
      <section
        class="w-full max-w-3xl rounded-m3-xl p-8 sm:p-12"
        style={{
          backgroundColor: 'var(--m3-surface-container)',
          boxShadow: 'var(--m3-elev-2)',
        }}
      >
        <h1 class="text-3xl sm:text-4xl font-semibold tracking-tight mb-2"
            style={{ color: 'var(--m3-on-surface)' }}>
          OpenHand · Web 通用消息平台
        </h1>
        <p class="text-base mb-8"
           style={{ color: 'var(--m3-on-surface-variant)' }}>
          Stage 1 脚手架：Vite + Preact + TypeScript + Tailwind v4 + M3 Expressive token，
          通过 <code>/api/meta</code> 与 Flutter 主题保持配色一致。
        </p>

        <div class="rounded-m3-md p-5 mb-6"
             style={{
               backgroundColor: 'var(--m3-surface)',
               border: '1px solid var(--m3-outline)',
             }}>
          <div class="flex items-center gap-2 mb-3">
            <span class="inline-block w-2.5 h-2.5 rounded-full"
                  style={{ backgroundColor: meta ? 'var(--m3-primary)' : 'var(--m3-outline)' }} />
            <span class="text-sm font-medium"
                  style={{ color: 'var(--m3-on-surface-variant)' }}>
              主题来源：{theme.source === 'api' ? '来自 /api/meta（与 OpenHand 主控制台同步）' : '默认 token'}
              {theme.error ? ` · 错误：${theme.error}` : ''}
            </span>
          </div>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {(
              [
                ['primary', theme.tokens.primary],
                ['surface', theme.tokens.surface],
                ['surfaceContainer', theme.tokens.surfaceContainer],
                ['outline', theme.tokens.outline],
              ] as const
            ).map(([name, color]) => (
              <div key={name} class="flex flex-col gap-1">
                <div class="h-12 rounded-m3-sm"
                     style={{ backgroundColor: color, border: '1px solid var(--m3-outline)' }} />
                <span class="text-xs font-mono"
                      style={{ color: 'var(--m3-on-surface-variant)' }}>
                  {name}
                </span>
                <span class="text-xs font-mono"
                      style={{ color: 'var(--m3-on-surface)' }}>
                  {color}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div class="rounded-m3-md p-5"
             style={{
               backgroundColor: 'var(--m3-surface)',
               border: '1px solid var(--m3-outline)',
             }}>
          <h2 class="text-lg font-semibold mb-3"
              style={{ color: 'var(--m3-on-surface)' }}>
            可访问 URL（点击复制）
          </h2>
          {urls.length === 0 ? (
            <p class="text-sm"
               style={{ color: 'var(--m3-on-surface-variant)' }}>
              {meta ? '当前 service 未返回 accessible_urls。' : '正在加载 …'}
            </p>
          ) : (
            <ul class="flex flex-wrap gap-2">
              {urls.map((url) => (
                <li key={url}>
                  <button
                    type="button"
                    onClick={() => void navigator.clipboard.writeText(url)}
                    class="px-3 py-1.5 rounded-m3-sm text-sm font-mono transition-colors"
                    style={{
                      backgroundColor: 'var(--m3-primary)',
                      color: 'var(--m3-on-primary)',
                      boxShadow: 'var(--m3-elev-1)',
                    }}
                    title={url === boundUrl ? '当前绑定 URL' : '局域网可访问 URL'}
                  >
                    {url}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <p class="mt-6 text-xs"
           style={{ color: 'var(--m3-on-surface-variant)' }}>
          后续阶段：登录 / 会话 / 多类型消息 / 文件 / Ops 仪表盘。
        </p>
      </section>
    </main>
  );
}
