import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import preact from '@preact/preset-vite';
import { defineConfig } from 'vite';

const OPENHAND_LOGO_PATH = fileURLToPath(
  new URL('../../assets/branding/openhand_logo.png', import.meta.url),
);

const MERMAID_VENDOR_PATTERNS = [
  'mermaid',
  '@mermaid-js',
  '@braintree/sanitize-url',
  'cytoscape',
  'd3',
  'dagre-d3',
  'dayjs',
  'es-toolkit',
  'khroma',
  'roughjs',
  'stylis',
  'ts-dedent',
  '@iconify/utils',
  '@upsetjs/venn',
  'langium',
  'chevrotain',
] as const;

const MARKDOWN_VENDOR_PATTERNS = [
  'highlight',
  'lowlight',
  'katex',
  'marked',
  'markdown',
  'remark',
  'rehype',
  'micromark',
  'mdast',
  'hast',
  'unified',
  'vfile',
  'bail',
  'trough',
  'zwitch',
  'ccount',
  'character-entities',
  'decode-named-character',
  'property-information',
  'space-separated-tokens',
  'comma-separated-tokens',
  'is-plain-obj',
  'html-url-attributes',
  'longest-streak',
  'escape-string-regexp',
  'estree-util-is-identifier-name',
] as const;

const FEATURE_CHUNK_RULES = [
  ['/features/sessions/', 'feature-sessions'],
  ['/features/logs/', 'feature-logs'],
  ['/features/ops/', 'feature-ops'],
  ['/features/harness/', 'feature-harness'],
  ['/features/toolbox/', 'feature-toolbox'],
  ['/features/files/', 'feature-files'],
  ['/features/plugins/', 'feature-plugins'],
  ['/features/settings/', 'feature-settings'],
] as const;

function includesAnyPattern(id: string, patterns: readonly string[]): boolean {
  return patterns.some((pattern) => id.includes(pattern));
}

function featureChunkNameFor(id: string): string | undefined {
  return FEATURE_CHUNK_RULES.find(([pattern]) => id.includes(pattern))?.[1];
}

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
    // vendor-mermaid 是第三方完整图表库（含 d3 + cytoscape 等），
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
            if (id.includes('preact') || id.includes('@preact')) {
              return 'vendor-preact';
            }
            // mermaid 体积巨大（>2 MB）且自成体系，单独拆包避免撑大 vendor。
            // 必须把 mermaid 的间接依赖（d3、cytoscape、roughjs 等）
            // 一并归入本 chunk，否则它们会落到 vendor 中，导致 vendor-mermaid
            // 仍需拉取 vendor，失去独立缓存意义，且可能引入循环引用。
            if (includesAnyPattern(id, MERMAID_VENDOR_PATTERNS)) {
              return 'vendor-mermaid';
            }
            // Markdown 生态统一桶：包含 highlight.js / lowlight / rehype-highlight
            // 及 react-markdown / remark / rehype / KaTeX / micromark / unified 等全部
            // 间接依赖。把 highlight 合并进来，消除 vendor-markdown
            // -> vendor-highlight 循环。
            if (includesAnyPattern(id, MARKDOWN_VENDOR_PATTERNS)) {
              return 'vendor-markdown';
            }
            return 'vendor';
          }
          return featureChunkNameFor(id);
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
