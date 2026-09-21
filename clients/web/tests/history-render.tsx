import { render } from 'preact';
import { Markdown } from '../src/components/Markdown';
import { MessageCard, markMessagesAsAppeared } from '../src/components/MessageCard';
import { VirtualMessageList } from '../src/features/sessions/components/SessionDetailPage';
import type { SessionMessage } from '../src/api/sessions';
import { MESSAGE_LIST_MAX_VISIBLE_ROWS } from '../src/shared/util/virtual_message_list_math';
import '../src/styles/global.css';

const root = document.getElementById('qa-root')!;
const result = document.getElementById('qa-result')!;
const checks: string[] = [];
function verify(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
  checks.push(message);
}
async function until(predicate: () => boolean) {
  const deadline = performance.now() + 15_000;
  while (!predicate()) {
    if (performance.now() >= deadline) throw new Error('等待渲染超时');
    await new Promise<void>((resolve) => setTimeout(resolve, 30));
  }
}
const table = '| 消息 | 状态 |\n| --- | --- |\n| 历史记录 | 正常 |';
const messages: SessionMessage[] = Array.from({ length: 1000 }, (_, index) => ({
  id: `消息-${index}`, kind: 'assistant', role: 'assistant',
  created_at: '2026-09-15T00:00:00Z', character_count: table.length,
  content: index % 2 ? table : '<div><strong>历史 HTML 卡片</strong><p>内容正常</p></div>',
}));
const scrollRef: { current: HTMLDivElement | null } = { current: null };
let settled = false;
function mount(session: string, items = messages) {
  settled = false;
  render(<div ref={scrollRef} style={{ height: '480px', overflowY: 'auto', width: '600px', maxWidth: '100%' }}>
    <VirtualMessageList key={session} messages={items} membershipKey={session}
      scrollContainerRef={scrollRef} revealTarget={null} highlightedMessageId={null}
      onInitialLayoutSettled={() => { settled = true; }}
      renderMessage={(message) => <Markdown source={message.content} deferInitialRender />} />
  </div>, root);
}

try {
  // 覆盖普通列表与虚拟列表的边界，短会话始终从顶部顺序排列。
  for (const width of [360, 1200]) {
    for (const count of [1, 4, 6, 7, 8]) {
      settled = false;
      const items = messages.slice(0, count);
      render(<section ref={scrollRef} class="oh-session-messages"
        style={{ height: '600px', overflowY: 'auto', width: `${width}px`, maxWidth: '100%' }}>
        <div class="oh-session-message-content oh-session-transcript-content">
          <VirtualMessageList key={`顶部-${width}-${count}`} messages={items} membershipKey={`顶部-${count}`}
            scrollContainerRef={scrollRef} revealTarget={null} highlightedMessageId={null}
            onInitialLayoutSettled={() => { settled = true; }}
            renderMessage={(message) => <div style={{ height: '44px' }}>{message.id}</div>} />
        </div>
      </section>, root);
      await until(() => settled && root.querySelectorAll('[data-message-id]').length === count);
      await new Promise<void>((resolve) => setTimeout(resolve, 250));
      const scroller = scrollRef.current!;
      const rows = Array.from(root.querySelectorAll<HTMLElement>('[data-message-id]'));
      verify(Math.abs(rows[0]!.getBoundingClientRect().top - scroller.getBoundingClientRect().top) < 1,
        `${width} 像素宽度、${count} 条消息从顶部开始排列`);
      verify(scroller.scrollTop === 0 && scroller.scrollHeight === scroller.clientHeight,
        `${width} 像素宽度、${count} 条消息不产生空白滚动区域`);
      verify(rows.every((row, index) => row.dataset.messageId === items[index]!.id),
        `${width} 像素宽度、${count} 条消息保持时间顺序`);
      render(null, root);
    }
  }
  // 高卡片下方仍处于列表预加载区，正文应等待真正接近视口。
  render(<div style={{ height: '200px', overflow: 'auto' }} id="视口探针">
    <div style={{ height: '1000px' }}>前一张长卡片</div>
    <div id="屏外正文"><Markdown source={table} deferInitialRender /></div>
  </div>, root);
  await new Promise<void>((resolve) => setTimeout(resolve, 250));
  verify(root.querySelector('#屏外正文 table') == null, '屏外 Markdown 不提前解析');
  root.querySelector('#屏外正文')!.scrollIntoView({ block: 'start' });
  await until(() => root.querySelector('#屏外正文 td') != null);
  verify(root.querySelector('#屏外正文 td')?.textContent === '历史记录', '进入视口后自动恢复完整 Markdown');
  render(null, root);
  window.scrollTo(0, 0);

  // 使用实际消息卡验证默认展开的短消息与默认折叠的思考消息都经过视口门控。
  const reasoning: SessionMessage = { ...messages[1]!, id: '屏外思考', kind: 'reasoning', content: table.repeat(10) };
  markMessagesAsAppeared([messages[1]!.id, reasoning.id]);
  render(<div style={{ height: '200px', overflow: 'auto' }}>
    <div style={{ height: '1000px' }}>前一张长卡片</div>
    <div id="屏外卡片"><MessageCard message={messages[1]!} /><MessageCard message={reasoning} /></div>
  </div>, root);
  await new Promise<void>((resolve) => setTimeout(resolve, 300));
  verify(root.querySelector('#屏外卡片 table') == null, '真实历史卡片与思考卡片在屏外不提前解析');
  root.querySelector('#屏外卡片')!.scrollIntoView({ block: 'start' });
  await until(() => root.querySelector('#屏外卡片 td') != null);
  verify(root.querySelector('#屏外卡片 td')?.textContent === '历史记录', '真实消息卡进入视口后显示富文本');
  render(null, root);
  window.scrollTo(0, 0);

  const streamProbe = (streaming: boolean) => <div style={{ marginTop: '2000px' }}>
    <Markdown source={table} deferInitialRender streaming={streaming} />
  </div>;
  render(streamProbe(false), root);
  await new Promise<void>((resolve) => setTimeout(resolve, 100));
  render(streamProbe(true), root);
  await until(() => root.querySelector('td') != null);
  render(streamProbe(false), root);
  verify(root.querySelector('td') != null, '流式结束后已显示的正文不会退回占位');
  render(null, root);

  mount('首个会话');
  verify(root.querySelectorAll('[data-message-id]').length <= 2, '千条混合消息首帧仅挂载两条');
  await until(() => settled && root.querySelector('[data-message-id="消息-999"] td') != null);
  verify(root.querySelectorAll('[data-message-id]').length <= MESSAGE_LIST_MAX_VISIBLE_ROWS, '稳定后挂载量仍受虚拟窗口限制');
  await until(() => root.querySelector('[data-message-id="消息-998"] strong') != null);
  verify(root.querySelector('[data-message-id="消息-998"] strong')?.textContent === '历史 HTML 卡片', '尾部 HTML 卡片正常净化并渲染');
  scrollRef.current!.scrollTop = 0;
  scrollRef.current!.dispatchEvent(new Event('scroll'));
  await until(() => root.querySelector('[data-message-id="消息-0"] strong') != null);
  verify(root.querySelectorAll('[data-message-id]').length <= MESSAGE_LIST_MAX_VISIBLE_ROWS, '翻到最早记录仍保持有界挂载');

  // 前插历史消息时沿用当前组件，不能先退回两条再重新解析已显示的卡片。
  const retainedRows = Array.from(root.querySelectorAll('[data-message-id]'));
  verify(retainedRows.length > 2, '前插检查前已完成首屏分帧');
  const earlier: SessionMessage = { ...messages[0]!, id: '更早消息' };
  render(<div ref={scrollRef} style={{ height: '480px', overflowY: 'auto', width: '600px', maxWidth: '100%' }}>
    <VirtualMessageList key="首个会话" messages={[earlier, ...messages]} membershipKey="前插历史"
      scrollContainerRef={scrollRef} revealTarget={null} highlightedMessageId={null}
      onInitialLayoutSettled={() => { settled = true; }}
      renderMessage={(message) => <Markdown source={message.content} deferInitialRender />} />
  </div>, root);
  verify(retainedRows.every((row) => row.isConnected), '前插历史不卸载当前已显示的消息节点');

  render(null, root);
  // 无限装饰动画不影响真实高度提交；正文展开后数帧内修正虚拟高度。
  const animatedItems = messages.slice(0, 10);
  const mountAnimated = (height: number) => render(<div ref={scrollRef}
    style={{ height: '480px', overflowY: 'auto', width: '600px', maxWidth: '100%' }}>
    <VirtualMessageList key="动画测高" messages={animatedItems} membershipKey="动画测高"
      scrollContainerRef={scrollRef} revealTarget={null} highlightedMessageId={null}
      onInitialLayoutSettled={() => { settled = true; }}
      renderMessage={() => <div style={{ height: `${height}px` }}><span style={{ animation: 'oh-placeholder-pulse 1s infinite' }}>加载中</span></div>} />
  </div>, root);
  mountAnimated(300);
  await until(() => root.querySelectorAll('[data-message-id]').length > 2);
  await new Promise<void>((resolve) => setTimeout(resolve, 200));
  const listBeforeResize = root.querySelector<HTMLElement>('[data-virtualized]')!;
  const heightBeforeResize = Number.parseFloat(listBeforeResize.style.height);
  mountAnimated(700);
  for (let frame = 0; frame < 10; frame++) {
    await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
  }
  verify(Number.parseFloat(listBeforeResize.style.height) > heightBeforeResize + 300,
    '持续微光动画下正文展开仍在十帧内更新虚拟高度');
  render(null, root);

  for (let index = 0; index < 20; index++) mount(`切换-${index}`);
  settled = false;
  mount('最终会话', messages.map((message) => ({ ...message, id: `新-${message.id}` })));
  await until(() => settled && root.querySelector('[data-message-id="新-消息-999"] td') != null);
  verify(root.querySelector('[data-message-id="消息-999"]') == null, '快速切换二十次后仅保留当前会话');
  render(null, root);
  const longMarkdown = '- **历史正文**：消息内容\n'.repeat(1500);
  const longMessages = messages.map((message) => ({
    ...message,
    id: `长正文-${message.id}`,
    content: longMarkdown,
    metadata: { content_format: 'markdown' },
  }));
  markMessagesAsAppeared(longMessages.map((message) => message.id));
  settled = false;
  render(<div ref={scrollRef} style={{ height: '480px', overflowY: 'auto', width: '600px', maxWidth: '100%' }}>
    <VirtualMessageList key="长正文" messages={longMessages} membershipKey="长正文"
      scrollContainerRef={scrollRef} revealTarget={null} highlightedMessageId={null}
      onInitialLayoutSettled={() => { settled = true; }}
      renderMessage={(message) => <MessageCard message={message} />} />
  </div>, root);
  await until(() => settled && root.querySelector('[data-message-id="长正文-消息-999"] .oh-markdown strong') != null);
  verify(root.querySelectorAll('[data-message-id]').length <= MESSAGE_LIST_MAX_VISIBLE_ROWS,
    '千条长正文消息仍仅挂载视口附近卡片');
  const renderedBodies = Array.from(root.querySelectorAll('.oh-markdown'));
  verify(renderedBodies.length > 0 && renderedBodies.every((body) => (body.textContent?.length ?? 0) <= 1200),
    '千条长正文首次仅解析折叠预览，正文开销不随历史总长度增长');
  render(null, root);
  document.title = '长会话渲染回归检查通过';
  result.textContent = `通过 ${checks.length} 项：\n${checks.join('\n')}`;
} catch (error) {
  document.title = '长会话渲染回归检查失败';
  result.textContent = `${checks.join('\n')}\n${String(error)}`;
  throw error;
}
