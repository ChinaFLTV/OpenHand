import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

// 产物输出到 ../../assets/web/，由 scripts/build_web.sh 调用 `pnpm build` 后
// Flutter rootBundle 直接拉取。入口 app.js / app.css 固定文件名便于服务端白名单
// 暴露；拆分 chunk 与派生 assets 使用内容 hash，避免旧 Service Worker / 浏览器缓存
// 把新 app.js 和旧 vendor chunk 混用导致 ESM export 错配。
export default defineConfig({
  plugins: [preact()],
  base: '/',
  build: {
    outDir: '../../assets/web',
    emptyOutDir: true,
    sourcemap: false,
    target: 'es2022',
    cssCodeSplit: false,
    // vendor-mermaid 是第三方完整图表库（含 d3 + cytoscape + katex 等），
    // 体积极大且不可控；把警告阈值提升到 3 MB，避免无意义的 chunk size 噪音。
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
        // 按 vendor 与重 feature 拆 chunk，把 app.js 主块缩小。
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (id.includes('preact') || id.includes('@preact')) return 'vendor-preact';
            // mermaid 体积巨大（>2 MB）且自成体系，单独拆包避免撑大 vendor。
            // 必须把 mermaid 的 transitive 依赖（d3、cytoscape、katex、roughjs 等）
            // 一并归入本 chunk，否则它们会落到 vendor 中，导致 vendor-mermaid
            // 仍需拉取 vendor，失去独立缓存意义，且可能引入循环引用。
            if (
              id.includes('mermaid')
              || id.includes('@mermaid-js')
              || id.includes('@braintree/sanitize-url')
              || id.includes('cytoscape')
              || id.includes('d3')
              || id.includes('dagre-d3')
              || id.includes('dayjs')
              || id.includes('es-toolkit')
              || id.includes('katex')
              || id.includes('khroma')
              || id.includes('roughjs')
              || id.includes('stylis')
              || id.includes('ts-dedent')
              || id.includes('@iconify/utils')
              || id.includes('@upsetjs/venn')
              || id.includes('langium')
              || id.includes('chevrotain')
            ) return 'vendor-mermaid';
            // Markdown 生态统一桶：包含 highlight.js / lowlight / rehype-highlight
            // 及 react-markdown / remark / rehype / micromark / unified 等全部 transitive
            // 依赖。把 highlight 合并进来，消除 vendor-markdown -> vendor-highlight 循环。
            if (
              id.includes('highlight')
              || id.includes('lowlight')
              || id.includes('marked')
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
