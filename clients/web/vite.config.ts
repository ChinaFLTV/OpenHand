import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

// 产物输出到 ../../assets/web/，由 scripts/build_web.sh 调用 `pnpm build` 后
// Flutter rootBundle 直接拉取；assetsDir 设为空字符串以让 index.html 与 .js/.css
// 同级输出，规避 shelf-router 的 <path|.+> 通配符匹配复杂度。
export default defineConfig({
  plugins: [preact()],
  base: '/',
  // @ts-expect-error vitest 注入的 test 字段, vite 类型不识别但运行无碍
  test: {
    environment: 'happy-dom',
    globals: true,
    include: ['src/**/*.test.{ts,tsx}'],
    setupFiles: ['./test/setup.ts'],
  },
  build: {
    outDir: '../../assets/web',
    emptyOutDir: true,
    sourcemap: false,
    target: 'es2022',
    cssCodeSplit: false,
    chunkSizeWarningLimit: 600,
    rollupOptions: {
      output: {
        // 用确定性文件名，避免每次构建产生新 hash 导致 git diff 噪声
        entryFileNames: 'app.js',
        chunkFileNames: 'chunks/[name].js',
        assetFileNames: (asset) => {
          if (asset.name?.endsWith('.css')) return 'app.css';
          return 'assets/[name][extname]';
        },
        // 按 vendor 与重 feature 拆 chunk，把 app.js 主块缩小。
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (id.includes('preact') || id.includes('@preact')) return 'vendor-preact';
            if (id.includes('highlight')) return 'vendor-highlight';
            // Markdown 生态完整桶到 vendor-markdown：react-markdown 自身、
            // 以及它依赖的 remark / micromark / mdast / hast / unified / vfile /
            // bail / is-plain-obj / trough / character-* / decode-named-* 等
            // 一整套 transitive 依赖。之前只匹配 'marked' / 'markdown' 把
            // unified / micromark 漏到了 vendor.js，让通用 vendor 关键路径无谓变胖。
            if (
              id.includes('marked')
              || id.includes('markdown')
              || id.includes('remark')
              || id.includes('rehype')
              || id.includes('micromark')
              || id.includes('mdast')
              || id.includes('hast')
              || id.includes('unified')
              || id.includes('vfile')
              || id.includes('bail')
              || id.includes('trough')
              || id.includes('zwitch')
              || id.includes('ccount')
              || id.includes('character-entities')
              || id.includes('decode-named-character')
              || id.includes('property-information')
              || id.includes('space-separated-tokens')
              || id.includes('comma-separated-tokens')
              || id.includes('is-plain-obj')
              || id.includes('html-url-attributes')
              || id.includes('longest-streak')
              || id.includes('escape-string-regexp')
              || id.includes('estree-util-is-identifier-name')
            ) return 'vendor-markdown';
            return 'vendor';
          }
          if (id.includes('/features/sessions/')) return 'feature-sessions';
          if (id.includes('/features/logs/')) return 'feature-logs';
          if (id.includes('/features/ops/')) return 'feature-ops';
          if (id.includes('/features/hardness/')) return 'feature-hardness';
          if (id.includes('/features/toolbox/')) return 'feature-toolbox';
          if (id.includes('/features/files/')) return 'feature-files';
          if (id.includes('/features/plugins/')) return 'feature-plugins';
          if (id.includes('/features/settings/')) return 'feature-settings';
          return undefined;
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
