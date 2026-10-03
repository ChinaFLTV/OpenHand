import { render } from 'preact';
import { act } from 'preact/test-utils';
import type { SessionMessage } from '../src/api/sessions';
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
let copied = 0;
let loaded = 0;
function mount(width: number, loading = false) {
  render(<div style={{ width, maxWidth: '100%', padding: 16, boxSizing: 'border-box', display: 'grid', gap: 16 }}>
    <MessageCard message={message} active onCopy={() => { copied++; }} />
    <MessageCard message={preview} fullContentLoading={loading} onLoadFullContent={() => { loaded++; }} />
    <MessageCard message={mutation} />
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
        verify(getComputedStyle(load).borderRadius === getComputedStyle(toggle).borderRadius, '完整内容按钮沿用原有操作圆角');
        verify([...card.querySelectorAll<HTMLElement>('.oh-tool-meta-chip')].every((node) => Math.abs(node.getBoundingClientRect().height - 24) < 1), '工具状态保持原有紧凑尺寸');
        const audioButtons = [...root.querySelectorAll<HTMLElement>('.oh-audio-icon-button')];
        verify(audioButtons.every((node) => node.getBoundingClientRect().height === (node.classList.contains('is-primary') ? 34 : 28)), '音频操作保持原有圆形尺寸');
        verify(getComputedStyle(root.querySelector<HTMLElement>('.oh-tool-section')!).backgroundColor === 'rgba(0, 0, 0, 0)', '工具分区保留原有轻量布局');
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
