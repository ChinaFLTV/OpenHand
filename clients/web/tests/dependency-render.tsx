import { render } from 'preact';
import { Markdown } from '../src/components/Markdown';
import '../src/styles/global.css';

const root = document.getElementById('qa-root')!;
const result = document.getElementById('qa-result')!;
const checks: string[] = [];
function verify(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
  checks.push(message);
}

try {
  render(<main>
    <section id="math"><Markdown source={'公式：\\(x^2 + y^2 = z^2\\)\n\n$$\\frac{1}{2}$$'} /></section>
    <section id="html"><Markdown format="html" source={'<div><strong>安全的中文内容</strong><a href="javascript:void(0)" onclick="void(0)">不安全链接</a><script>void(0)</script></div>'} /></section>
    <section id="table"><Markdown source={'| 标题 | 状态 |\n| --- | --- |\n| 会话 | 已完成 |'} /></section>
  </main>, root);
  const deadline = performance.now() + 15_000;
  while (performance.now() < deadline && (
    root.querySelectorAll('#math .katex').length < 2
    || !root.querySelector('#html strong')
  )) {
    root.querySelector<HTMLButtonElement>('#html .oh-html-progressive-button')?.click();
    await new Promise<void>((resolve) => setTimeout(resolve, 50));
  }
  verify(root.querySelectorAll('#math .katex').length === 2, '行内与块级数学公式均完成渲染');
  verify(root.querySelector('#math .katex-error') == null, '数学公式没有解析错误');
  verify(root.querySelector('#html strong')?.textContent === '安全的中文内容', 'HTML 净化保留安全内容与样式结构');
  verify(root.querySelector('#html script, #html [onclick], #html [href^="javascript:"]') == null, 'HTML 净化移除脚本、事件与不安全链接');
  verify(root.querySelector('#table td')?.textContent === '会话', 'Markdown 表格正常渲染');
  render(null, root);
  document.title = '依赖渲染回归检查通过';
  result.textContent = `通过 ${checks.length} 项：\n${checks.join('\n')}`;
} catch (error) {
  document.title = '依赖渲染回归检查失败';
  result.textContent = String(error);
  throw error;
}
