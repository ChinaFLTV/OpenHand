import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import preact from '@preact/preset-vite';
import { defineConfig } from 'vite';

const OPENHAND_LOGO_PATH = fileURLToPath(
  new URL('../../assets/branding/openhand_logo.png', import.meta.url),
);

// 产物输出到 ../../assets/web/，由 scripts/build_web.sh 调用 `pnpm build` 后
// Flutter rootBundle 直接拉取。入口 app.js / app.css 固定文件名便于服务端白名单
// 暴露；拆分 chunk 与派生 assets 使用内容 hash，避免旧 Service Worker / 浏览器缓存
// 把新 app.js 和旧 vendor chunk 混用导致 ESM export 错配。
export default defineConfig({
  plugins: [
    preact(),
    {
      name: 'openhand-branding-asset',
      generateBundle() {
        this.emitFile({
          type: 'asset',
          fileName: 'openhand_logo.png',
          source: readFileSync(OPENHAND_LOGO_PATH),
        });
      },
    },
  ],
  base: '/',
  build: {
    outDir: '../../assets/web',
    emptyOutDir: true,
    sourcemap: false,
    target: 'es2022',
    cssCodeSplit: false,
    // Mermaid 完整图表库体积较大；把警告阈值提升到 3 MB，
    // 避免对已经按需加载的第三方模块产生无意义噪音。
    chunkSizeWarningLimit: 3000,
    rollupOptions: {
      output: {
        // 入口固定，派生 chunk 带内容 hash：兼顾服务端路由稳定性与缓存正确性。
        entryFileNames: 'app.js',
        chunkFileNames: 'chunks/[name]-[hash].js',
        assetFileNames: (asset) => {
          if (asset.name?.endsWith('.css')) return 'app.css';
          return 'assets/[name]-[hash][extname]';
        },
      },
    },
  },
  server: {
    port: 5180,
    strictPort: true,
    proxy: {
      // 开发态把 /api 代理到本地启动的 Flutter app（默认 8848）
      '/api': {
        target: 'http://localhost:8848',
        changeOrigin: true,
      },
    },
  },
});
