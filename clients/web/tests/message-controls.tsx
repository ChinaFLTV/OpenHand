import { render } from 'preact';
import { act } from 'preact/test-utils';
import type { SessionMessage } from '../src/api/sessions';
import { Markdown } from '../src/components/Markdown';
import { codeLanguageLabel } from '../src/shared/util/code_block';
import { MessageMedia } from '../src/components/MessageMedia';
import { MessageCard, markMessagesAsAppeared } from '../src/components/MessageCard';
import { syncLangFromAppPreferences, t } from '../src/i18n';
import { fileMutationLabel, toolDisplayName } from '../src/shared/util/tool_display_name';
import { setRemoteReducedMotion } from '../src/hooks/useReducedMotion';
import { applyThemeTokens, defaultThemeTokens } from '../src/theme/tokens';
import '../src/styles/global.css';

const root = document.getElementById('qa-root')!;
const result = document.getElementById('qa-result')!;
const checks: string[] = [];
const verify = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
  checks.push(message);
};
const message: SessionMessage = {
  id: '工具控件检查', kind: 'tool_call', role: 'assistant', content: '',
  created_at: '2026-10-03T00:00:00Z', character_count: 0,
  metadata: {
    tool_name: 'MachineTerminalExec', tool_execution_status: 'success',
    tool_execution_command: 'systemctl status openhand',
    tool_arguments: JSON.stringify({ command: 'systemctl status openhand', timeout_ms: 30000, purpose: '检查服务运行状态' }),
    tool_execution_working_directory: `/workspace/${'服务项目目录/'.repeat(12)}`,
    tool_execution_stdout: '服务已启动，健康检查通过。\n'.repeat(80),
    tool_execution_exit_code: 0, tool_execution_duration_ms: 1450,
  },
};
const preview: SessionMessage = {
  id: '完整内容检查', kind: 'assistant', role: 'assistant', content: '这段回复展示了需要按需加载的完整内容。',
  created_at: message.created_at, metadata: { _openhand_content_preview: true }, character_count: 18000,
};
const audio: SessionMessage = {
  id: '音频控件检查', kind: 'assistant', role: 'assistant', content: '', created_at: message.created_at, character_count: 0,
  metadata: { attachments: [{ path: '/workspace/audio.wav', kind: 'audio', name: '音频检查.wav' }] },
};
const mutation: SessionMessage = {
  id: '文件变更检查', kind: 'file_mutation_summary', role: 'assistant', content: '', created_at: message.created_at, character_count: 0,
  metadata: { file_mutation_kind: 'delete', file_mutation_path: `/workspace/${'很长的目录/'.repeat(10)}file.dart`, round_summary_record_count: 12 },
};
let clipboardText = '';
let downloadedBlob: Blob | null = null;
Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async (text: string) => { clipboardText = text; } } });
const originalCreateObjectURL = URL.createObjectURL.bind(URL);
URL.createObjectURL = (blob: Blob | MediaSource) => {
  if (blob instanceof Blob) downloadedBlob = blob;
  return originalCreateObjectURL(blob);
};
const fenceSource = ['```shell', 'systemctl status openhand', '```', '```', '服务检查通过', '```', '```json', '{"status":"running"}', '```', '```diff', '@@ -1 +1 @@', '-旧内容', '+新内容', '```'].join('\n');
let copied = 0;
let loaded = 0;
function mount(width: number, loading = false) {
  render(<div style={{ width, maxWidth: '100%', padding: 16, boxSizing: 'border-box', display: 'grid', gap: 16 }}>
    <MessageCard message={message} active onCopy={() => { copied++; }} />
    <MessageCard message={preview} fullContentLoading={loading} onLoadFullContent={() => { loaded++; }} />
    <MessageCard message={mutation} />
    <div class="qa-markdown"><Markdown source={fenceSource} streaming /></div>
    <MessageMedia message={audio} sessionId="控件检查" />
  </div>, root);
}
try {
  setRemoteReducedMotion(true);
  markMessagesAsAppeared([message.id, preview.id, mutation.id, audio.id]);
  for (const lang of ['zh_Hans', 'zh_Hant', 'en', 'ja']) {
    syncLangFromAppPreferences(lang);
    for (const dark of [false, true]) {
      applyThemeTokens(dark ? {
        ...defaultThemeTokens, brightness: 'dark', primary: '#AAC7FF', secondary: '#BCC7DB', tertiary: '#DEBCE2',
        surface: '#111318', surfaceContainerLow: '#191C22', surfaceContainer: '#1D2026',
        onSurface: '#E2E2E9', onSurfaceVariant: '#C3C6D0', outline: '#8D919B', outlineVariant: '#43464F',
      } : defaultThemeTokens);
      for (const width of [320, 760]) {
        await act(async () => { render(null, root); mount(width); });
        const card = root.querySelector<HTMLElement>('.oh-message-card')!;
        verify(root.textContent?.includes(toolDisplayName('MachineTerminalExec')) === true, `${lang} 工具名按当前语言显示`);
        verify(root.textContent?.includes({ zh_Hans: '成功', zh_Hant: '成功', en: 'Succeeded', ja: '成功' }[lang]!) === true, `${lang} 执行状态按当前语言显示`);
        verify(toolDisplayName('mcp__server__Read') === 'mcp__server__Read', '外部工具标识保持原样');
        verify(fileMutationLabel('delete') !== 'delete', `${lang} 文件操作标签已翻译`);
        const toggle = root.querySelector<HTMLButtonElement>('.oh-tool-toggle-button')!;
        await act(async () => { toggle.click(); });
        verify(root.querySelector<HTMLElement>('.oh-tool-section-pre') != null, '工具分区可展开');
        const copy = [...root.querySelectorAll<HTMLButtonElement>('.oh-message-action-button')]
          .find((button) => button.textContent === t('common.copy'));
        verify(copy != null, '选中卡片可显示复制操作');
        const before = copied;
        await act(async () => { copy!.click(); });
        verify(copied === before + 1, '复制操作正常触发');
        const load = root.querySelector<HTMLButtonElement>('.oh-message-content-preview-action')!;
        verify(load.textContent === t('message.contentPreview.load'), `${lang} 完整内容按钮按当前语言显示`);
        verify(load.getBoundingClientRect().height >= 28 && load.getBoundingClientRect().height <= 32, `${width}px 完整内容按钮使用紧凑尺寸`);
        verify(getComputedStyle(load).borderRadius === getComputedStyle(document.documentElement).getPropertyValue('--m3-radius-sm').trim(), '完整内容按钮沿用原有操作圆角');
        verify([...card.querySelectorAll<HTMLElement>('.oh-tool-meta-chip')].every((node) => Math.abs(node.getBoundingClientRect().height - 24) < 1), '工具状态保持原有紧凑尺寸');
        const audioButtons = [...root.querySelectorAll<HTMLElement>('.oh-audio-icon-button')];
        verify(audioButtons.every((node) => node.getBoundingClientRect().height === (node.classList.contains('is-primary') ? 34 : 28)), '音频操作保持原有圆形尺寸');
        const sections = [...root.querySelectorAll<HTMLElement>('.oh-tool-section')];
        const stdoutSection = sections.find((section) => section.querySelector('strong')?.textContent === t('detail.tool.stdout'))!;
        const stdout = stdoutSection.querySelector<HTMLElement>('pre')!;
        const toolbarButtons = [...root.querySelectorAll<HTMLButtonElement>('.oh-tool-section-header button, .oh-code-block-header button')];
        verify(toolbarButtons.every((button) => Math.abs(button.getBoundingClientRect().height - 28) < 1), '工具分区与代码工具栏按钮高度统一');
        verify(sections.every((section) => getComputedStyle(section).backgroundColor !== 'rgba(0, 0, 0, 0)'), '工具分区使用主题纯色背景');
        verify(stdoutSection.textContent?.includes(codeLanguageLabel('text')) === true, `${lang} 输出类型按当前语言显示`);
        verify(sections.some((section) => section.textContent?.includes(codeLanguageLabel('shell'))), `${lang} 命令类型按当前语言显示`);
        const stdoutCopy = stdoutSection.querySelector<HTMLButtonElement>(`button[aria-label="${t('common.copy')}"]`)!;
        await act(async () => { stdoutCopy.click(); });
        verify(clipboardText === (message.metadata!.tool_execution_stdout as string).trim(), '折叠输出复制完整原文');
        await act(async () => { stdoutSection.querySelector<HTMLButtonElement>(`button[aria-label="${t('codeBlock.download')}"]`)!.click(); });
        verify(await downloadedBlob!.text() === (message.metadata!.tool_execution_stdout as string).trim(), '折叠输出下载完整原文');
        const wrapButton = stdoutSection.querySelector<HTMLButtonElement>('button[aria-pressed]')!;
        await act(async () => { wrapButton.click(); });
        verify(getComputedStyle(stdout).whiteSpace === 'pre', '关闭换行后正文可横向滚动');
        const expandedBefore = stdoutSection.querySelector('button[aria-expanded]')!.getAttribute('aria-expanded');
        await act(async () => { stdout.click(); });
        verify(stdoutSection.querySelector('button[aria-expanded]')!.getAttribute('aria-expanded') === expandedBefore, '点击正文不会触发折叠');
        verify([...root.querySelectorAll<HTMLElement>('.oh-code-block, .oh-tool-section')].every((node) => node.scrollWidth <= node.clientWidth + 1), `${width}px 内部代码工具栏不溢出`);
        verify([...root.querySelectorAll<HTMLElement>('.oh-code-block, .oh-tool-section')].every((node) => getComputedStyle(node).boxShadow === 'none'), '内部卡片不使用阴影');
        const codeLabels = [...root.querySelectorAll('.qa-markdown .oh-code-block-lang')].map((node) => node.textContent);
        verify(codeLabels.includes(codeLanguageLabel('text')) && codeLabels.includes(codeLanguageLabel('shell')) && codeLabels.includes('JSON'), `${lang} 普通围栏、终端及 JSON 标签正确显示`);
        const loadsBefore = loaded;
        await act(async () => { load.click(); mount(width, true); });
        const busyLoad = root.querySelector<HTMLButtonElement>('.oh-message-content-preview-action')!;
        verify(busyLoad.disabled && busyLoad.textContent === t('message.contentPreview.loading'), `${lang} 加载状态已翻译且按钮禁用`);
        await act(async () => { busyLoad.click(); });
        verify(loaded === loadsBefore + 1, '加载中不会重复触发请求');
        verify([...root.querySelectorAll<HTMLElement>('.oh-message-card, .oh-audio-result-card')].every((node) => node.scrollWidth <= node.clientWidth + 1), `${width}px 窗口长路径不撑破卡片`);
        verify(getComputedStyle(card).boxShadow === 'none', '卡片使用描边反馈');
        verify([...root.querySelectorAll<HTMLElement>('.oh-message-card, .oh-tool-section, .oh-message-content-preview-notice, .oh-message-content-preview-action, .oh-message-action-button, .oh-tool-meta-chip')]
          .every((node) => getComputedStyle(node).backgroundImage === 'none'), '消息控件不使用渐变');
      }
    }
  }
  for (const lang of ['zh_Hans', 'zh_Hant', 'en', 'ja']) {
    syncLangFromAppPreferences(lang);
    for (const kind of ['tool_call', 'hook'] as const) {
      for (const content of ['', '工具结果预览']) {
        const deferred: SessionMessage = {
          ...message, id: `工具延迟读取-${lang}-${kind}-${content}`, kind, content,
          metadata: { tool_name: 'MachineTerminalExec', tool_execution_status: 'success',
            _openhand_content_preview: true, _openhand_deferred_display: true },
        };
        const complete: SessionMessage = { ...deferred, metadata: message.metadata };
        let requests = 0;
        function mountDeferred(current = deferred, loading = false) {
          render(<MessageCard message={current} fullContentLoading={loading} onLoadFullContent={(requested) => {
            verify(requested.id === deferred.id, '子板块读取对应的工具消息');
            requests++;
            mountDeferred(deferred, true);
          }} />, root);
        }
        markMessagesAsAppeared([deferred.id]);
        await act(async () => { render(null, root); mountDeferred(); });
        verify(requests === 0, '工具预览不会提前读取完整记录');
        verify(root.querySelector('.oh-message-content-preview-notice') === null, `${kind} 移除外层完整内容入口及其占位`);
        const toggle = root.querySelector<HTMLButtonElement>('.oh-tool-toggle-button')!;
        verify(toggle != null && toggle.textContent === t('detail.tool.body.expand'), `${lang} 空正文或短预览仍有子板块完整内容入口`);
        await act(async () => { toggle.click(); });
        const busy = root.querySelector<HTMLButtonElement>('.oh-tool-toggle-button')!;
        verify(busy.disabled && busy.textContent === t('message.contentPreview.loading'), `${lang} 工具读取状态已翻译且按钮禁用`);
        await act(async () => { busy.click(); });
        verify(requests === 1, '工具加载中不会重复触发请求');
        await act(async () => { mountDeferred(); });
        verify(!root.querySelector<HTMLButtonElement>('.oh-tool-toggle-button')!.disabled, '读取失败后原入口恢复可用');
        await act(async () => { root.querySelector<HTMLButtonElement>('.oh-tool-toggle-button')!.click(); });
        verify(requests === 2, '工具读取失败后可从子板块重试');
        await act(async () => { mountDeferred(complete); });
        verify(root.textContent?.includes(toolDisplayName('MachineTerminalExec')) === true, '完整记录恢复后保留工具结构与名称');
        const stdout = [...root.querySelectorAll<HTMLElement>('.oh-tool-section')]
          .find((section) => section.querySelector('strong')?.textContent === t('detail.tool.stdout'))!;
        verify(stdout != null, `${kind} 完整读取后标准输出可见`);
        await act(async () => { stdout.querySelector<HTMLButtonElement>(`button[aria-label="${t('common.copy')}"]`)!.click(); });
        verify(clipboardText === (complete.metadata!.tool_execution_stdout as string).trim(), '移除外层入口后仍能复制完整输出');
      }
    }
  }
  applyThemeTokens(defaultThemeTokens);
  syncLangFromAppPreferences('zh_Hans');
  await act(async () => { render(null, root); mount(760); });
  document.title = '消息控件检查通过';
  result.textContent = `通过 ${checks.length} 项检查`;
} catch (error) {
  document.title = '消息控件检查失败';
  result.textContent = `${checks.join('\n')}\n检查失败：${String(error)}`;
  throw error;
}
