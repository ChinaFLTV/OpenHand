import { render } from 'preact';
import { collectGalleryMedia, MediaPreviewDialog } from '../src/components/MessageMedia';
import { ImageMessageContext, resolveImageGallery, type ImageGalleryEntry } from '../src/components/image_gallery';
import type { SessionMessage } from '../src/api/sessions';
import '../src/styles/global.css';

const root = document.getElementById('qa-root')!;
const result = document.getElementById('qa-result')!;
const checks: string[] = [];
function verify(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
  checks.push(message);
}
async function until(predicate: () => boolean) {
  const deadline = performance.now() + 5000;
  while (!predicate()) {
    if (performance.now() >= deadline) throw new Error('等待图片导航超时');
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}
const picture = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="480" height="320"><rect width="480" height="320" fill="#a5b966"/></svg>');
function message(id: string, content: string): SessionMessage {
  return { id, content, role: 'user', kind: 'user', created_at: '2026-09-18T00:00:00Z', character_count: content.length };
}

try {
  const quoted = message('引用', `<blockquote><img src="${picture}" alt="引用图"></blockquote>`);
  const messages = [message('原图', quoted.content), quoted, message('下一条', `![后一张](${picture})`)];
  let located = '';
  const images = function* (): Iterable<ImageGalleryEntry> {
    for (const message of messages) {
      for (const item of collectGalleryMedia(message)) {
        yield { item, url: item.path, messageId: message.id, onLocate: () => { located = message.id; } };
      }
    }
  };
  const entries = [...images()];
  verify(entries.length === 3, 'Markdown、HTML 引用图片均进入图库');
  verify(resolveImageGallery(images(), entries[1], quoted.id)?.index === 1, '重复原图按引用所在消息定位');
  const local = collectGalleryMedia(message('本地图', '> ![本地引用](/tmp/quoted.png)\n\n![重复](/tmp/quoted.png)'));
  verify(local.length === 1 && local[0].path === '/tmp/quoted.png' && !local[0].isDirectUrl, '本地引用图片去重并走会话附件接口');
  const escaped = collectGalleryMedia(message('实体', '<blockquote><img src="https://example.com/a.png?a=1&amp;b=2"></blockquote>'));
  verify(escaped[0].path.endsWith('?a=1&b=2'), 'HTML 图片地址正确解码实体');

  render(<ImageMessageContext.Provider value={{ messageId: quoted.id, images }}>
    <MediaPreviewDialog item={entries[1].item} url={entries[1].url} onClose={() => render(null, root)} />
  </ImageMessageContext.Provider>, root);
  const counter = () => document.querySelector('.oh-image-gallery-navigation')?.textContent?.trim();
  await until(() => counter() === '2 / 3');
  verify(!!document.querySelector('button[aria-label="上一张"]') && !!document.querySelector('button[aria-label="下一张"]'), '真实预览弹窗显示前后导航按钮');
  document.querySelector<HTMLButtonElement>('button[aria-label="下一张"]')!.click();
  await until(() => counter() === '3 / 3');
  verify(document.querySelector<HTMLButtonElement>('button[aria-label="下一张"]')!.disabled, '末图禁用继续向后导航');
  document.querySelector<HTMLButtonElement>('button[aria-label="上一张"]')!.click();
  await until(() => counter() === '2 / 3');
  document.querySelector<HTMLButtonElement>('button[aria-label="定位到消息"]')!.click();
  await until(() => located === '引用');
  verify(!document.querySelector('.oh-image-gallery-navigation'), '退场完成后定位回引用所在消息');
  result.textContent = `通过 ${checks.length} 项\n${checks.join('\n')}`;
  document.documentElement.dataset.qa = 'passed';
} catch (error) {
  result.textContent = String(error);
  document.documentElement.dataset.qa = 'failed';
  throw error;
}
