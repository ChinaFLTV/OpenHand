import { render } from 'preact';
import { Markdown } from '../src/components/Markdown';
import { MessageCard, markMessagesAsAppeared } from '../src/components/MessageCard';
import { VirtualMessageList } from '../src/features/sessions/components/SessionDetailPage';
import type { SessionMessage } from '../src/api/sessions';
import { MESSAGE_LIST_MAX_VISIBLE_ROWS } from '../src/shared/util/virtual_message_list_math';
import { clearTranscriptScrollActivity, markTranscriptScrollActivity } from '../src/shared/ui/transcript_scroll_activity';
import sessionDetailSource from '../src/features/sessions/components/SessionDetailPage.tsx?raw';
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

  const largeDecision: SessionMessage = { ...messages[1]!, id: '屏外大型决策', content:
    '```openhand-decision\n' + JSON.stringify({
      questions: { 判断: { type: 'noul', instructions: '判断依据'.repeat(2500) } },
      answers: { 判断: { type: 'noul', noul: 0.8 } },
    }) + '\n```' };
  markMessagesAsAppeared([largeDecision.id]);
  render(<div style={{ height: '200px', overflow: 'auto' }}>
    <div style={{ height: '1000px' }}>前一张长卡片</div>
    <div id="屏外大型决策"><MessageCard message={largeDecision} /></div>
  </div>, root);
  await new Promise<void>((resolve) => setTimeout(resolve, 250));
  verify(root.querySelector('.oh-decision-block') == null, '大型决策历史消息在屏外不绕过渲染预算');
  root.querySelector('#屏外大型决策')!.scrollIntoView({ block: 'start' });
  await until(() => root.querySelector('.oh-decision-bar-fill') != null);
  verify(root.querySelectorAll('.oh-decision-block').length === 1, '大型决策进入视口后恢复完整卡片');
  render(null, root);
  window.scrollTo(0, 0);

  const denseSource = '**密集内容** '.repeat(4000);
  render(<Markdown source={denseSource} deferInitialRender={false} />, root);
  await until(() => root.querySelector('.oh-markdown p') != null);
  verify(root.querySelector('.oh-markdown p')!.textContent === denseSource, '密集 Markdown 回退后保留完整原文');
  verify(root.querySelectorAll('.oh-markdown *').length < 4, '密集 Markdown 不构建成千上万个 DOM 节点');
  render(null, root);

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
  // 完整卡片超过旧的测高上限时，虚拟列表仍须为全文预留空间。
  settled = false;
  const tallItems = messages.slice(0, 7);
  render(<div ref={scrollRef} style={{ height: '480px', overflowY: 'auto', width: '600px' }}>
    <VirtualMessageList key="超高卡片" messages={tallItems} membershipKey="超高卡片"
      scrollContainerRef={scrollRef} revealTarget={null} highlightedMessageId={null}
      onInitialLayoutSettled={() => { settled = true; }}
      renderMessage={(message) => <div style={{ height: message.id === tallItems.at(-1)!.id ? '80000px' : '44px' }}>{message.id}</div>} />
  </div>, root);
  await until(() => settled);
  verify(Number.parseFloat(root.querySelector<HTMLElement>('[data-virtualized]')!.style.height) >= 80000,
    '八万像素的完整卡片保留真实滚动范围');
  render(null, root);
  // 模拟图片解码、HTML 测高：屏外卡片增高不能把正在阅读的消息挤走。
  settled = false;
  const resizeItems = messages.map((message) => ({ ...message, id: `异步测高-${message.id}` }));
  const sizes = new Map<string, number>();
  const mountResize = () => render(<div ref={scrollRef} class="oh-session-messages"
    style={{ height: '480px', overflowY: 'auto', width: '600px' }}>
    <VirtualMessageList key="异步测高" messages={resizeItems} membershipKey="异步测高"
      scrollContainerRef={scrollRef} revealTarget={null} highlightedMessageId={null}
      onInitialLayoutSettled={() => { settled = true; }}
      renderMessage={(message) => <div style={{ height: `${sizes.get(message.id) ?? 180}px` }}>{message.id}</div>} />
  </div>, root);
  const frames = async (count = 10) => {
    for (let frame = 0; frame < count; frame++) {
      await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
    }
  };
  mountResize();
  await until(() => settled);
  scrollRef.current!.scrollTop = 95000;
  scrollRef.current!.dispatchEvent(new Event('scroll'));
  await frames();
  const scrollerTop = () => scrollRef.current!.getBoundingClientRect().top;
  const mountedRows = () => Array.from(root.querySelectorAll<HTMLElement>('[data-message-id]'));
  const reading = mountedRows().find((row) => row.getBoundingClientRect().bottom > scrollerTop())!;
  const readingTop = reading.getBoundingClientRect().top;
  const preceding = mountedRows().find((row) => row.getBoundingClientRect().bottom <= scrollerTop())!;
  verify(Boolean(preceding), '异步测高用例包含屏外预加载卡片');
  sizes.set(preceding.dataset.messageId!, 1080);
  mountResize();
  await frames();
  verify(reading.isConnected && Math.abs(reading.getBoundingClientRect().top - readingTop) < 1,
    '屏外图片或 HTML 增高九百像素后阅读位置不变');
  sizes.set(preceding.dataset.messageId!, 90);
  mountResize();
  await frames();
  verify(reading.isConnected && Math.abs(reading.getBoundingClientRect().top - readingTop) < 1,
    '屏外多媒体收缩后阅读位置不变');
  let compensatedFrames = 0;
  for (let frame = 0; frame < 180; frame++) {
    const anchor = mountedRows().find((row) => row.getBoundingClientRect().bottom > scrollerTop())!;
    const top = anchor.getBoundingClientRect().top;
    const oldPixels = scrollRef.current!.scrollTop;
    scrollRef.current!.scrollTop += frame < 90 ? -24 : 24;
    const shift = oldPixels - scrollRef.current!.scrollTop;
    if (frame === 20 || frame === 110) {
      const above = mountedRows().find((row) => row.getBoundingClientRect().bottom <= scrollerTop());
      if (above) {
        sizes.set(above.dataset.messageId!, frame === 20 ? 1080 : 90);
        mountResize();
        compensatedFrames += 1;
      }
    }
    scrollRef.current!.dispatchEvent(new Event('scroll'));
    await frames(2);
    if (anchor.isConnected && Math.abs(anchor.getBoundingClientRect().top - top - shift) >= 1) {
      throw new Error(`千条消息往返滚动第 ${frame} 帧出现用户请求之外的位移`);
    }
  }
  verify(compensatedFrames === 2, '往返滚动期间覆盖两次异步卡片高度变化');
  verify(true, '千条消息连续往返一百八十帧保持阅读位置');
  verify(mountedRows().length <= MESSAGE_LIST_MAX_VISIBLE_ROWS, '往返滚动与异步测高后挂载量仍有界');
  scrollRef.current!.scrollTop = scrollRef.current!.scrollHeight;
  scrollRef.current!.dispatchEvent(new Event('scroll'));
  await frames();
  const tailPreceding = mountedRows().find((row) => row.getBoundingClientRect().bottom <= scrollerTop())!;
  sizes.set(tailPreceding.dataset.messageId!, 1080);
  mountResize();
  await frames();
  const tail = mountedRows().find((row) => row.dataset.messageId === resizeItems.at(-1)!.id)!;
  const tailTop = tail.getBoundingClientRect().top;
  sizes.set(tailPreceding.dataset.messageId!, 90);
  mountResize();
  await frames();
  verify(tail.isConnected && Math.abs(tail.getBoundingClientRect().top - tailTop) < 1,
    '接近底部时屏外卡片收缩不重复补偿浏览器夹紧');
  render(null, root);

  // 将页面真实输入与尺寸监听接到虚拟列表，覆盖同一次触底后的图片解码与 HTML 增高。
  const sliceSource = (start: string, end: string) => {
    const from = sessionDetailSource.indexOf(start);
    const to = sessionDetailSource.indexOf(end, from);
    if (from < 0 || to <= from) throw new Error('未找到真实滚动入口');
    return sessionDetailSource.slice(from, to);
  };
  for (const count of [4, 1000]) {
    const bottomContentRef: { current: HTMLDivElement | null } = { current: null };
    const paused = { current: false };
    const userBottomAnchor = { current: false };
    const lastTop = { current: 0 };
    const lastIntent = { current: 0 };
    const bottomItems = messages.slice(0, count).map(message => ({ ...message, id: `触底-${count}-${message.id}` }));
    let htmlHeight = 0;
    let imageSource: string | undefined;
    settled = false;
    const mountBottom = () => render(<section ref={scrollRef} class="oh-session-messages"
      style={{ height: '480px', overflowY: 'auto', width: '600px' }}>
      <div ref={bottomContentRef} class="oh-session-message-content">
        <VirtualMessageList key="手动触底" messages={bottomItems} membershipKey="手动触底"
          followBottom={!paused.current} scrollContainerRef={scrollRef} revealTarget={null} highlightedMessageId={null}
          onInitialLayoutSettled={() => { settled = true; }}
          renderMessage={message => message === bottomItems.at(-1)
            ? <div><p>最终回复中的图片与 HTML</p><img src={imageSource} style={{ width: '100%', display: 'block' }} />
                <div style={{ height: `${htmlHeight}px` }}>延迟就绪的 HTML 正文</div><p>最终回复结束</p></div>
            : <div style={{ height: '180px' }}>{message.id}</div>} />
      </div>
    </section>, root);
    mountBottom();
    await until(() => settled);
    const bottomScroller = scrollRef.current!;
    lastTop.current = bottomScroller.scrollTop;
    const bindings = {
      useCallback: (callback: () => void) => callback,
      mainRef: scrollRef, messagesContentRef: bottomContentRef,
      autoFollowRef: { current: true }, autoFollowPausedRef: paused, userBottomAnchorRef: userBottomAnchor,
      lastScrollTopRef: lastTop, lastUserScrollIntentAtRef: lastIntent,
      programmaticScrollUntilRef: { current: 0 }, composerLayoutPinnedRef: { current: false },
      isNearBottomRef: { current: true }, markTranscriptScrollActivity,
      hasRecentUserScrollIntent: () => Date.now() - lastIntent.current <= 1200,
      isComposerLayoutTransitioning: () => false, cancelFollowSettle() {}, cancelAutoFollowMotion() {},
      setAutoFollowEnabled() {},
      setAutoFollowPaused(update: (value: boolean) => boolean) { update(paused.current); mountBottom(); },
      scrollMessagesToBottom() { bottomScroller.scrollTop = bottomScroller.scrollHeight - bottomScroller.clientHeight; },
      AUTO_FOLLOW_USER_SCROLL_INTENT_MS: 1200, AUTO_FOLLOW_WHEEL_INTENT_EPSILON_PX: 0,
      AUTO_FOLLOW_NEAR_BOTTOM_PX: 64, AUTO_FOLLOW_RESUME_BOTTOM_PX: 1,
    };
    const setupBottom = new Function(...Object.keys(bindings), [
      sliceSource('  const setAutoFollowPausedValue =', '  const hasRecentUserScrollIntent =')
        .replace('(value: boolean)', '(value)'),
      sliceSource('    const retainUserBottomAnchor =', '    const handlePointerDown =')
        .replace('(event: WheelEvent)', '(event)'),
      sliceSource('    let lastTouchY:', '    function recalc() {')
        .replace('lastTouchY: number | null', 'lastTouchY').replaceAll('(event: TouchEvent)', '(event)')
        .replaceAll('event.touches[0]!', 'event.touches[0]'),
      sliceSource('    function recalc() {', '    recalc();'),
      sliceSource('    const handleScroll = () => {', "    el?.addEventListener('scroll'"),
      "mainRef.current.addEventListener('wheel', handleWheel); mainRef.current.addEventListener('scroll', handleScroll);",
      'const disconnect = (() => {',
      sliceSource('    const target = messagesContentRef.current;', '  }, [autoFollow, autoFollowPaused, hasRecentUserScrollIntent]);'),
      '})(); return { handleTouchStart, handleTouchMove, cleanup() { disconnect(); mainRef.current.removeEventListener("wheel", handleWheel); mainRef.current.removeEventListener("scroll", handleScroll); } };',
    ].join('\n'));
    const bottomControls = setupBottom(...Object.values(bindings));
    try {
      bottomScroller.dispatchEvent(new WheelEvent('wheel', { deltaY: -240 }));
      bottomScroller.scrollTop -= 240;
      bottomScroller.dispatchEvent(new Event('scroll'));
      await frames();
      bottomScroller.dispatchEvent(new WheelEvent('wheel', { deltaY: 10000 }));
      bottomScroller.scrollTop = bottomScroller.scrollHeight;
      bottomScroller.dispatchEvent(new Event('scroll'));
      await frames(2);
      verify(userBottomAnchor.current, `${count} 条消息一次向下滑到旧底部后记住触底意图`);
      imageSource = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';
      mountBottom();
      await until(() => root.querySelector<HTMLImageElement>('img')?.naturalHeight === 1);
      await frames();
      const actualBottom = () => root.querySelector<HTMLElement>(`[data-message-id="${bottomItems.at(-1)!.id}"]`)!.getBoundingClientRect().bottom;
      const viewportBottom = () => bottomScroller.getBoundingClientRect().top + bottomScroller.clientHeight;
      verify(Math.abs(actualBottom() - viewportBottom()) < 1, `${count} 条消息图片解码增高后无需第二次下滑即可看到真实最后一行`);
      htmlHeight = 900;
      mountBottom();
      await frames();
      verify(Math.abs(actualBottom() - viewportBottom()) < 1, `${count} 条消息同次触底后的 HTML 再次增高仍停在真实尾部`);
      bottomScroller.dispatchEvent(new WheelEvent('wheel', { deltaY: -.01 }));
      let readingPixels = bottomScroller.scrollTop;
      htmlHeight = 1400;
      mountBottom();
      await frames();
      verify(Math.abs(bottomScroller.scrollTop - readingPixels) < 1 && actualBottom() > viewportBottom() + 400,
        `${count} 条消息微小反向上滑在下一次滚动事件前撤销贴底，后续增高不抢回`);
      bottomControls.handleTouchStart({ touches: [{ clientY: 400 }] });
      bottomScroller.scrollTop = bottomScroller.scrollHeight;
      bottomScroller.dispatchEvent(new Event('scroll'));
      await frames(2);
      for (const clientY of [300, 250]) bottomControls.handleTouchMove({ touches: [{ clientY }] });
      htmlHeight = 1900;
      mountBottom();
      await frames();
      verify(userBottomAnchor.current && Math.abs(actualBottom() - viewportBottom()) < 1,
        `${count} 条消息触摸触底后继续下滑，没有位置更新也能补齐 HTML 测高`);
      bottomControls.handleTouchMove({ touches: [{ clientY: 250.01 }] });
      readingPixels = bottomScroller.scrollTop;
      htmlHeight = 2400;
      mountBottom();
      await frames();
      verify(!userBottomAnchor.current && Math.abs(bottomScroller.scrollTop - readingPixels) < 1,
        `${count} 条消息同一次触摸微小反向，立即停止后续测高追底`);
      clearTranscriptScrollActivity();
      await frames(30);
      verify(Math.abs(bottomScroller.scrollTop - readingPixels) < 1, `${count} 条消息滚动静默后不重新拉回底部`);
      verify(root.querySelectorAll('[data-message-id]').length <= MESSAGE_LIST_MAX_VISIBLE_ROWS, `${count} 条消息连续触底测高保持有界挂载`);
    } finally {
      bottomControls.cleanup();
      clearTranscriptScrollActivity();
      render(null, root);
    }
  }
  document.title = '长会话渲染回归检查通过';
  result.textContent = `通过 ${checks.length} 项：\n${checks.join('\n')}`;
} catch (error) {
  document.title = '长会话渲染回归检查失败';
  result.textContent = `${checks.join('\n')}\n${String(error)}`;
  throw error;
}
