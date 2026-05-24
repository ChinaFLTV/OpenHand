import { test, expect } from '@playwright/test';

const sessionId = 'mobile-session';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem('openhand.web.token', 'mobile-test-token');
    localStorage.setItem('openhand.web.profile', JSON.stringify({ username: 'mobile-test' }));
  });

  await page.route('**/api/meta', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        service: {
          auth_enabled: true,
          session_management_enabled: true,
          plan_mode_enabled: true,
          ops_enabled: true,
          logging_enabled: true,
        },
        templates: [],
        conversation_modes: ['normal', 'image', 'plan'],
        message_types: ['text', 'attachment'],
        models: [{
          key: 'mock-model',
          provider_id: 'mock',
          provider: 'mock',
          model_id: 'mock-vision-model-with-long-name',
          label: 'Mock Vision Model',
          supports_attachments: true,
          supports_image_generation: true,
        }],
      }),
    });
  });

  await page.route(`**/api/sessions/${sessionId}`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        session: {
          id: sessionId,
          title: '移动端窄屏会话布局测试',
          template_id: 'programming_expert',
          template_name: '编程专家',
          created_at: '2026-05-08T00:00:00.000Z',
          updated_at: '2026-05-08T00:00:10.000Z',
          mode: 'chat',
          full_access_permission: false,
          last_model_key: 'mock-model',
          message_count: 4,
          total_tokens: 12345,
          tool_message_count: 1,
          compression_point_count: 1,
          last_message_preview: 'OK',
          send_phase: 'idle',
        },
        runtime: {
          send_phase: 'idle',
          can_stop: false,
          last_error: null,
        },
      }),
    });
  });

  await page.route(`**/api/sessions/${sessionId}/messages?**`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        session: {
          id: sessionId,
          title: '移动端窄屏会话布局测试',
          template_id: 'programming_expert',
          template_name: '编程专家',
          created_at: '2026-05-08T00:00:00.000Z',
          updated_at: '2026-05-08T00:00:10.000Z',
          mode: 'chat',
          full_access_permission: false,
          last_model_key: 'mock-model',
          message_count: 4,
          total_tokens: 12345,
          tool_message_count: 1,
          compression_point_count: 1,
          last_message_preview: 'OK',
          send_phase: 'idle',
        },
        items: [
          {
            id: 'm1',
            kind: 'text',
            role: 'user',
            content: '请检查这个很窄的移动端会话页面。',
            created_at: '2026-05-08T00:00:01.000Z',
            character_count: 17,
          },
          {
            id: 'm2',
            kind: 'reasoning',
            role: 'assistant',
            content: '第一行思考\n第二行计划\n第三行检查布局\n第四行检查滚动\n第五行检查工具卡\n第六行收束',
            created_at: '2026-05-08T00:00:02.000Z',
            character_count: 45,
          },
          {
            id: 'm3',
            kind: 'tool_call',
            role: 'assistant',
            content: '检查视口宽度和滚动容器',
            created_at: '2026-05-08T00:00:03.000Z',
            character_count: 12,
            metadata: {
              tool_name: 'LayoutProbe',
              tool_execution_status: 'success',
              tool_execution_stdout: 'viewport=360 scrollWidth=360 ok=true',
              tool_arguments: '{"viewport":360}',
            },
          },
          {
            id: 'm4',
            kind: 'assistant',
            role: 'assistant',
            content: '已加载。这里放一段稍长的流式回复，用于确保消息卡片、Reasoning、工具卡片、顶部栏和输入区都不会造成横向滚动。',
            created_at: '2026-05-08T00:00:04.000Z',
            character_count: 58,
            model_label: 'Mock Vision Model',
            metadata: { streaming: true },
          },
        ],
        offset: 0,
        limit: 80,
        total: 2,
        has_more: false,
        send_phase: 'idle',
        last_error: null,
      }),
    });
  });

  await page.route(`**/api/sessions/${sessionId}/events?**`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'text/event-stream',
      headers: {
        'cache-control': 'no-cache',
      },
      body: '\n',
    });
  });
});

test('session detail fits a 360px mobile viewport without horizontal overflow', async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 740 });
  await page.goto(`/threads/${sessionId}`);

  await expect(page.locator('.oh-session-composer')).toBeVisible();
  await expect(page.locator('.oh-composer-permission-control')).toBeVisible();
  await expect(page.locator('.oh-message-card')).toHaveCount(4);
  await expect(page.locator('.oh-message-badge-toggle')).toHaveCount(2);
  await expect(page.locator('.oh-message-badge-toggle').first()).toBeVisible();

  const layout = await page.evaluate(() => {
    const composer = document.querySelector('.oh-session-composer')?.getBoundingClientRect();
    const toolbar = document.querySelector('.oh-composer-toolbar')?.getBoundingClientRect();
    const permission = document.querySelector('.oh-composer-permission-control')?.getBoundingClientRect();
    const main = document.querySelector('.oh-session-detail-page')?.getBoundingClientRect();
    const cards = Array.from(document.querySelectorAll('.oh-message-card'))
      .map((card) => card.getBoundingClientRect());
    const cardLeft = Math.min(...cards.map((card) => card.left));
    const cardRight = Math.max(...cards.map((card) => card.right));
    return {
      viewportWidth: window.innerWidth,
      documentWidth: document.documentElement.scrollWidth,
      bodyWidth: document.body.scrollWidth,
      mainWidth: main?.width ?? 0,
      composerWidth: composer?.width ?? 0,
      toolbarWidth: toolbar?.width ?? 0,
      permissionWidth: permission?.width ?? 0,
      cardCount: cards.length,
      cardLeft,
      cardRight,
    };
  });

  expect(layout.documentWidth).toBeLessThanOrEqual(layout.viewportWidth + 1);
  expect(layout.bodyWidth).toBeLessThanOrEqual(layout.viewportWidth + 1);
  expect(layout.mainWidth).toBeLessThanOrEqual(layout.viewportWidth + 2);
  expect(layout.composerWidth).toBeLessThanOrEqual(layout.viewportWidth + 1);
  expect(layout.toolbarWidth).toBeLessThanOrEqual(layout.composerWidth + 1);
  expect(layout.permissionWidth).toBeLessThanOrEqual(40);
  expect(layout.cardCount).toBe(4);
  expect(layout.cardLeft).toBeGreaterThanOrEqual(-1);
  expect(layout.cardRight).toBeLessThanOrEqual(layout.viewportWidth + 1);
});