import { render } from 'preact';
import { act } from 'preact/test-utils';
import type { SessionMessage } from '../src/api/sessions';
import { Markdown } from '../src/components/Markdown';
import { MessageCard, markMessagesAsAppeared } from '../src/components/MessageCard';
import { VirtualMessageList } from '../src/features/sessions/components/SessionDetailPage';
import { syncRemoteDialogMotionSettings } from '../src/hooks/useDialogMotionSettings';
import { MESSAGE_LIST_MAX_VISIBLE_ROWS } from '../src/shared/util/virtual_message_list_math';
import '../src/styles/global.css';

const root = document.getElementById('qa-root')!;
const result = document.getElementById('qa-result')!;
const checks: string[] = [];
const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));
function verify(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
  checks.push(message);
}
async function until(predicate: () => boolean) {
  const deadline = performance.now() + 5000;
  while (!predicate()) {
    if (performance.now() >= deadline) throw new Error('等待正文渲染超时');
    await wait(20);
  }
}
const durationMs = 180;
const content = '### 已渲染的历史正文\n\n' + Array(12).fill('反复展开与折叠时，保留 **格式化正文** 和 `代码片段`，避免加载状态闪回。\n').join('\n');
const reasoning: SessionMessage = {
  id: '折叠回归思考', kind: 'reasoning', role: 'assistant', content,
  created_at: '2026-09-16T00:00:00Z', character_count: content.length,
};
const body = () => root.querySelector<HTMLElement>('.oh-message-card-body-motion')!;
const sizeAnimations = () => body().getAnimations({ subtree: true }).filter((animation) =>
  (animation.effect as KeyframeEffect).getKeyframes().some((frame) => 'height' in frame || 'maxHeight' in frame));
const toggle = () => root.querySelector<HTMLButtonElement>('.oh-message-badge-toggle')!;
const collapsed = () => root.querySelector('.oh-reasoning-collapsible-body')?.getAttribute('data-collapsed') === 'true';
async function clickToggle() {
  await act(async () => { toggle().click(); });
}

try {
  // 同一轮中立即反向切换，检查加载许可不会回退。
  const mountDeferred = (deferred: boolean) => render(<div style={{ marginTop: '2000px' }}>
    <Markdown source="### 历史正文\n\n**已显示的内容**" deferInitialRender={deferred} />
  </div>, root);
  mountDeferred(true);
  await wait(100);
  mountDeferred(false);
  const initialContent = root.querySelector('strong');
  verify(initialContent != null, '主动展开立即显示正文');
  mountDeferred(true);
  verify(root.querySelector('strong') === initialContent, '快速折叠不能让已显示正文退回加载状态');
  render(null, root);

  syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: durationMs });
  markMessagesAsAppeared([reasoning.id]);
  await act(async () => { render(<div style={{ width: '680px', maxWidth: '100%', padding: '20px' }}><MessageCard message={reasoning} /></div>, root); });
  await until(() => root.querySelector('.oh-markdown h3') != null);
  await wait(80);
  const originalHeading = root.querySelector('.oh-markdown h3');
  const collapsedTextWidth = originalHeading!.getBoundingClientRect().width;
  const collapsedHeight = body().getBoundingClientRect().height;
  let transientPlaceholder = false;
  const observer = new MutationObserver((records) => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node instanceof Element && (node.matches('.oh-markdown-pending-preview, .oh-html-body-placeholder') || node.querySelector('.oh-markdown-pending-preview, .oh-html-body-placeholder'))) transientPlaceholder = true;
      }
    }
  });
  observer.observe(root, { childList: true, subtree: true });
  await clickToggle();
  verify(!collapsed(), '思考卡正常进入展开态');
  verify(sizeAnimations().length === 1, '展开只使用一套尺寸动画');
  verify(sizeAnimations()[0]!.effect?.getTiming().duration === durationMs, '尺寸动画遵循全局时长');
  await wait(50);
  const intermediateHeight = body().getBoundingClientRect().height;
  await wait(durationMs + 40);
  const expandedHeight = body().getBoundingClientRect().height;
  verify(intermediateHeight > collapsedHeight && intermediateHeight < expandedHeight + 12, '正文高度逐帧展开且超调有界');
  verify(Math.abs(originalHeading!.getBoundingClientRect().width - collapsedTextWidth) < 1, '展开折叠保持正文宽度，避免滚动条引起文字重排');
  await clickToggle();
  verify(root.querySelector('.oh-reasoning-collapsible-body')!.getBoundingClientRect().height > collapsedHeight,
    '收起从完整正文开始裁剪，不先隐藏文字再收缩空白');
  await clickToggle();
  await wait(durationMs + 40);
  for (let cycle = 0; cycle < 20; cycle++) {
    await clickToggle();
    await wait(20);
    verify(root.querySelector('.oh-markdown h3') === originalHeading && originalHeading!.isConnected, `第 ${cycle + 1} 次快速切换保留正文节点`);
  }
  await wait(durationMs + 80);
  verify(Math.abs(body().getBoundingClientRect().height - expandedHeight) < 2, '反复打断动画最终收敛到正确高度');
  verify(!transientPlaceholder, '整个展开折叠过程不重新插入占位内容');
  await act(async () => { syncRemoteDialogMotionSettings({ entrance_style: 'none', exit_style: 'none' }); });
  await clickToggle();
  verify(sizeAnimations().length === 0 && collapsed(), '关闭全局动效立即折叠且没有残留动画');
  verify(root.querySelector('.oh-markdown h3') === originalHeading, '关闭动效仍保持正文实例');
  render(null, root);
  await wait(durationMs + 40);
  verify(root.childElementCount === 0, '卸载后动画回调不恢复旧节点');

  for (const format of ['markdown', 'html'] as const) {
    const source = format === 'html'
      ? `<article><h3>完整 HTML 正文</h3>${'<p>保留 <strong>已渲染内容</strong> 与交互状态。</p>'.repeat(80)}</article>`
      : `${content.repeat(5)}\n\n## 完整正文尾部标记`;
    const message: SessionMessage = { ...reasoning, id: `响应折叠-${format}`, kind: 'assistant', content: source, metadata: { content_format: format } };
    markMessagesAsAppeared([message.id]);
    syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: durationMs });
    await act(async () => { render(<div style={{ width: '680px', maxWidth: '100%' }}><MessageCard message={message} /></div>, root); });
    if (format === 'html') {
      await until(() => root.querySelector('.oh-html-progressive-button') != null);
      await act(async () => { root.querySelector<HTMLButtonElement>('.oh-html-progressive-button')!.click(); });
    } else {
      verify(!root.textContent?.includes('完整正文尾部标记'), '折叠 Markdown 首次只解析有界预览');
      await clickToggle();
      await until(() => root.textContent?.includes('完整正文尾部标记') === true);
      verify(root.textContent?.includes('完整正文尾部标记') === true, '展开后恢复完整 Markdown 正文');
    }
    await until(() => root.querySelector('h3') != null);
    await wait(80);
    const heading = root.querySelector('h3');
    transientPlaceholder = false;
    await clickToggle();
    verify(sizeAnimations().length === 1, `${format} 响应卡使用统一尺寸动画`);
    for (let cycle = 0; cycle < 8; cycle++) {
      await wait(25);
      await clickToggle();
      verify(root.querySelector('h3') === heading, `${format} 第 ${cycle + 1} 次切换保留正文`);
    }
    await act(async () => { syncRemoteDialogMotionSettings({ entrance_style: 'none', exit_style: 'none' }); });
    verify(sizeAnimations().length === 0, `${format} 动画中关闭全局动效立即收敛`);
    verify(!transientPlaceholder, `${format} 响应卡不回退到加载内容`);
    render(null, root);
  }

  for (const kind of ['reasoning', 'assistant', 'tool', 'mcp', 'skill', 'tool_call', 'hook'] as const) {
    for (const format of ['markdown', 'plain_text'] as const) {
      const message: SessionMessage = { ...reasoning, id: `内部滚动-${kind}-${format}`, kind,
        content: content.repeat(5), metadata: { content_format: format } };
      markMessagesAsAppeared([message.id]);
      await act(async () => { render(<div style={{ width: '680px', maxWidth: '100%' }}><MessageCard message={message} /></div>, root); });
      const preview = root.querySelector<HTMLElement>('.oh-reasoning-collapsible-body')!;
      await until(() => preview.scrollHeight > preview.clientHeight);
      verify(preview.dataset.collapsed === 'true' && getComputedStyle(preview).overflowY === 'auto',
        `${kind}/${format} 折叠正文保持内部滚动`);
      preview.scrollTop = 60;
      await act(async () => { preview.dispatchEvent(new Event('scroll')); });
      await wait(40);
      verify(preview.scrollTop > 0, `${kind}/${format} 滚动位置不会被测高恢复覆盖`);
      verify(getComputedStyle(preview).overscrollBehaviorY === 'contain', `${kind}/${format} 边界滚动不传递给会话`);
      for (let cycle = 0; cycle < 3; cycle++) {
        preview.scrollTop = preview.scrollHeight;
        await act(async () => { preview.dispatchEvent(new Event('scroll')); });
        await wait(40);
        const bottom = preview.scrollTop;
        preview.scrollTop -= 60;
        await act(async () => { preview.dispatchEvent(new Event('scroll')); });
        await wait(260);
        verify(preview.scrollTop < bottom - 30, `${kind}/${format} 第 ${cycle + 1} 次触底后反向滚动保持位置`);
      }
      await clickToggle();
      verify(preview.dataset.collapsed === 'false', `${kind}/${format} 胶囊实际展开正文`);
      await clickToggle();
      verify(preview.dataset.collapsed === 'true', `${kind}/${format} 胶囊实际折叠正文`);
      render(null, root);
    }
  }

  syncRemoteDialogMotionSettings({ entrance_style: 'spring_scale', exit_style: 'spring_scale', duration_ms: durationMs });
  const messages = Array.from({ length: 100 }, (_, index) => ({ ...reasoning, id: `虚拟折叠-${index}` }));
  markMessagesAsAppeared(messages.map((message) => message.id));
  const scrollRef: { current: HTMLDivElement | null } = { current: null };
  let settled = false;
  await act(async () => { render(<div ref={scrollRef} style={{ height: '480px', overflowY: 'auto', width: '680px', maxWidth: '100%' }}>
    <VirtualMessageList messages={messages} membershipKey="折叠回归"
      scrollContainerRef={scrollRef} revealTarget={null} highlightedMessageId={null}
      onInitialLayoutSettled={() => { settled = true; }}
      renderMessage={(message) => <MessageCard message={message} />} />
  </div>, root); });
  await until(() => settled && root.querySelector('[data-message-id="虚拟折叠-99"] h3') != null);
  await wait(100);
  const row = root.querySelector<HTMLElement>('[data-message-id="虚拟折叠-99"]')!;
  const heading = row.querySelector('h3');
  for (let cycle = 0; cycle < 12; cycle++) {
    await act(async () => { row.querySelector<HTMLButtonElement>('.oh-message-badge-toggle')!.click(); });
    await wait(cycle % 3 === 0 ? durationMs + 50 : 25);
    verify(row.isConnected && row.querySelector('h3') === heading, `虚拟列表第 ${cycle + 1} 次折叠不回收正在操作的卡片`);
  }
  await wait(durationMs + 80);
  verify(root.querySelectorAll('[data-message-id]').length <= MESSAGE_LIST_MAX_VISIBLE_ROWS, '连续操作后虚拟列表挂载量仍有界');
  observer.disconnect();
  render(null, root);
  document.title = '消息折叠回归检查通过';
  result.textContent = `通过 ${checks.length} 项：\n${checks.join('\n')}`;
} catch (error) {
  document.title = '消息折叠回归检查失败';
  result.textContent = `${checks.join('\n')}\n检查失败：${String(error)}`;
  throw error;
}
