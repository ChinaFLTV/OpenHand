import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';
// 产物输出到 ../../assets/web/，由 scripts/build_web.sh 调用 `pnpm build` 后
// Flutter rootBundle 直接拉取；assetsDir 设为空字符串以让 index.html 与 .js/.css
// 同级输出，规避 shelf-router 的 <path|.+> 通配符匹配复杂度。
export default defineConfig({
    plugins: [preact()],
    base: './',
    build: {
        outDir: '../../assets/web',
        emptyOutDir: true,
        sourcemap: false,
        target: 'es2022',
        cssCodeSplit: false,
        rollupOptions: {
            output: {
                // 用确定性文件名，避免每次构建产生新 hash 导致 git diff 噪声
                entryFileNames: 'app.js',
                chunkFileNames: 'chunks/[name].js',
                assetFileNames: (asset) => {
                    if (asset.name?.endsWith('.css'))
                        return 'app.css';
                    return 'assets/[name][extname]';
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
