import { test, expect } from '@playwright/test';

// 烟雾测试: 登录页能加载, 标题正确, 关键 input 可见。
// 跑前需 `pnpm dev` (或将 baseURL 指到任意可访问的 OpenHand Web 实例)。
test('login page renders', async ({ page }) => {
  await page.goto('/login');
  await expect(page).toHaveTitle(/OpenHand/);
  // 输入框: 配对码 (或服务端使用的鉴权字段)
  const input = page.locator('input').first();
  await expect(input).toBeVisible();
});

test('SPA shell loads home redirect', async ({ page }) => {
  await page.goto('/');
  // 未登录会被路由到 /login; 登录态会落到主页. 任一情况下 body 都应该挂载。
  await expect(page.locator('#root')).toBeVisible();
});
