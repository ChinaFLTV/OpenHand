import { defineConfig, devices } from '@playwright/test';

// Playwright e2e 配置. baseURL 默认走本地 vite dev server (5180);
// 真正运行需先 `pnpm dev` 在另一个 terminal 起来, 然后 `pnpm e2e`。
// CI 环境可通过 OPENHAND_WEB_BASE_URL 覆盖, 直接打远端 staging。
export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  fullyParallel: true,
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL: process.env.OPENHAND_WEB_BASE_URL ?? 'http://localhost:5180',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
