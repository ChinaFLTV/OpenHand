import { render } from 'preact';
import { Markdown } from '../src/components/Markdown';
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
  render(<div ref={scrollRef} style={{ height: '480px', overflowY: 'auto', width: '600px', maxWidth: '100%' }}>
    <VirtualMessageList key={session} messages={items} membershipKey={session}
      scrollContainerRef={scrollRef} revealTarget={null} highlightedMessageId={null}
      onInitialLayoutSettled={() => { settled = true; }}
      renderMessage={(message) => <Markdown source={message.content} deferInitialRender />} />
  </div>, root);
}

try {
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

  for (let index = 0; index < 20; index++) mount(`切换-${index}`);
  settled = false;
  mount('最终会话', messages.map((message) => ({ ...message, id: `新-${message.id}` })));
  await until(() => settled && root.querySelector('[data-message-id="新-消息-999"] td') != null);
  verify(root.querySelector('[data-message-id="消息-999"]') == null, '快速切换二十次后仅保留当前会话');
  render(null, root);
  document.title = '长会话渲染回归检查通过';
  result.textContent = `通过 ${checks.length} 项：\n${checks.join('\n')}`;
} catch (error) {
  document.title = '长会话渲染回归检查失败';
  result.textContent = `${checks.join('\n')}\n${String(error)}`;
  throw error;
}
