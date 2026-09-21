import { render } from 'preact';
import { MessageCard, markMessagesAsAppeared } from '../src/components/MessageCard';
import { VirtualMessageList } from '../src/features/sessions/components/SessionDetailPage';
import type { SessionMessage } from '../src/api/sessions';
import { markTranscriptScrollActivity, clearTranscriptScrollActivity } from '../src/shared/ui/transcript_scroll_activity';
import '../src/styles/global.css';

const root = document.getElementById('qa-root')!;
const result = document.getElementById('qa-result')!;
const frame = () => new Promise<void>(resolve => requestAnimationFrame(() => resolve()));
const content = '```openhand-decision\n' + JSON.stringify({
  questions: { 分类: { type: 'choice', instructions: '评估这项方案的执行方向与预期结果', criteria: { 甲: null, 乙: null, 丙: null, 丁: null } } },
  answers: { 分类: { type: 'choice', choice: '甲', probabilities: { 甲: .4, 乙: .3, 丙: .2, 丁: .1 } } },
}) + '\n```';
const messages: SessionMessage[] = Array.from({ length: 30 }, (_, index) => ({
  id: `决策-${index}`, role: 'assistant', kind: 'assistant', content, character_count: content.length,
  created_at: '2026-09-21T00:00:00Z',
}));
const scrollRef: { current: HTMLDivElement | null } = { current: null };
let settled = false;
const onSettled = () => { settled = true; };
const checks: string[] = [];
function mount() {
  render(<section ref={scrollRef} class="oh-session-messages" style={{ height: '650px', width: '700px', maxWidth: '100%', overflow: 'auto' }}>
    <VirtualMessageList messages={messages} membershipKey="决策" scrollContainerRef={scrollRef}
      revealTarget={null} highlightedMessageId={null} onInitialLayoutSettled={onSettled}
      renderMessage={message => <MessageCard message={message} />} />
  </section>, root);
}
try {
  for (const active of [true, false]) {
    render(<MessageCard message={{ ...messages[0]!, id: '新响应', content: '', character_count: 0 }} streaming={active} />, root);
    await frame();
    render(<MessageCard message={{ ...messages[0]!, id: '新响应' }} streaming={active} />, root);
    for (let i = 0; i < 30; i++) {
      await frame();
      if (root.querySelectorAll('.oh-decision-block').length !== 1) throw new Error(`完整响应第 ${i} 帧未显示完整决策，响应中=${active}`);
    }
    render(null, root);
  }
  checks.push('完整决策响应立即成卡，不经过逐字截断');
  markMessagesAsAppeared(messages.map(message => message.id));
  mount();
  for (let i = 0; i < 180; i++) await frame();
  if (!settled || !root.querySelector('.oh-decision-block')) throw new Error('决策卡片未就绪');
  const scroller = scrollRef.current!;
  let samples = 0;
  for (let i = 0; i < 600; i++) {
    const bounds = scroller.getBoundingClientRect();
    const before = [...root.querySelectorAll<HTMLElement>('[data-message-id]')]
      .map(row => ({ row, rect: row.getBoundingClientRect() }))
      .filter(({ rect }) => rect.bottom > bounds.top && rect.top < bounds.bottom);
    markTranscriptScrollActivity();
    const oldScroll = scroller.scrollTop;
    scroller.scrollTop += i < 300 ? -12 : 12;
    const shift = oldScroll - scroller.scrollTop;
    await frame();
    for (const { row, rect } of before) {
      if (!row.isConnected) continue;
      const after = row.getBoundingClientRect();
      if (after.bottom <= bounds.top || after.top >= bounds.bottom) continue;
      samples++;
      const unexpected = after.top - rect.top - shift;
      if (Math.abs(unexpected) > 1.5) throw new Error(`第 ${i} 帧 ${row.dataset.messageId} 额外移动 ${unexpected.toFixed(2)} 像素`);
    }
  }
  clearTranscriptScrollActivity();
  if (samples < 500) throw new Error(`采样不足：${samples}`);
  result.textContent = `通过：${samples} 次可见消息逐帧位置检查\n${checks.join('\n')}`;
  document.documentElement.dataset.qa = 'passed';
} catch (error) {
  clearTranscriptScrollActivity();
  result.textContent = String(error);
  document.documentElement.dataset.qa = 'failed';
}
