import { type PluginSummary, pluginDiagnostics } from '../../../api/plugins';
import { DialogFrame, DialogHeader, DialogActionButton, createStandardDialogFrameAppearance } from '../../../components/DialogFrame';
import { DIALOG_ACCENT, DialogGlyph, DialogIconBadge, DialogSectionCard } from '../../../components/DialogChrome';
import { useDialogExitMotion } from '../../../hooks/useDialogExitMotion';
import { copyTextToClipboard } from '../../../utils/clipboard';
import { showSnackbar } from '../../../components/Snackbar';
import { t } from '../../../i18n';

export function PluginDiagnosticsDialog({ plugin, pluginName, onClose }: {
  plugin?: PluginSummary;
  pluginName: string;
  onClose: () => void;
}) {
  const { closing, requestClose } = useDialogExitMotion(onClose);
  const diagnostics = plugin ? pluginDiagnostics(plugin) : [];
  const errors = diagnostics.filter((item) => item.severity === 'error').length;
  const errorLabel = t('plugins.status.error', '错误');
  const warningLabel = t('plugins.warning', '警告');
  const title = `${pluginName} · ${t('plugins.diagnostics', '诊断消息')}`;
  const copy = async (message: string) => {
    const ok = await copyTextToClipboard(message);
    showSnackbar(ok ? t('common.copied', '已复制') : t('common.copyFailed', '复制失败'), {
      tone: ok ? 'success' : 'error',
    });
  };

  return (
    <DialogFrame
      closing={closing}
      onRequestClose={requestClose}
      ariaLabel={title}
      {...createStandardDialogFrameAppearance({
        panelClassName: 'w-full rounded-m3-xl overflow-hidden flex flex-col',
        panelSurface: { maxWidth: '640px', maxHeight: 'min(82dvh, 720px)' },
      })}
    >
      <DialogHeader
        title={title}
        subtitle={`${errorLabel} ${errors} · ${warningLabel} ${diagnostics.length - errors}`}
        icon={<DialogIconBadge accent={DIALOG_ACCENT.primary}><DialogGlyph name="file" /></DialogIconBadge>}
        onClose={requestClose}
        closeLabel={t('common.close', '关闭')}
        closeDisabled={closing}
      />
      <div class="min-h-0 overflow-y-auto p-5 space-y-3" style={{ overflowWrap: 'anywhere' }}>
        {diagnostics.length === 0 ? (
          <DialogSectionCard
            title={plugin
              ? t('plugins.noDiagnostics', '当前没有错误或警告')
              : t('plugins.noLongerListed', '插件已不在当前列表中')}
            accent={plugin ? DIALOG_ACCENT.success : DIALOG_ACCENT.primary}
            icon={<DialogGlyph name={plugin ? 'check' : 'file'} />}
          >
            <p class="text-sm oh-text-muted">{t('plugins.diagnosticsLive', '诊断信息随插件状态自动更新。')}</p>
          </DialogSectionCard>
        ) : diagnostics.map((item) => (
          <DialogSectionCard
            key={item.severity}
            title={item.severity === 'error' ? errorLabel : warningLabel}
            accent={item.severity === 'error' ? DIALOG_ACCENT.error : DIALOG_ACCENT.warning}
            icon={<DialogGlyph name="alert" />}
            trailing={<DialogActionButton tone="ghost" disabled={closing} onClick={() => void copy(item.message)}>
              {t('common.copy', '复制')}
            </DialogActionButton>}
          >
            <p class="text-sm leading-relaxed whitespace-pre-wrap select-text">{item.message}</p>
          </DialogSectionCard>
        ))}
      </div>
      {diagnostics.length > 0 ? (
        <div class="px-5 py-3 flex justify-end" style={{ borderTop: '1px solid var(--m3-outline-variant)' }}>
          <DialogActionButton tone="secondary" disabled={closing} onClick={() => void copy(
            diagnostics.map((item) => `${item.severity === 'error' ? errorLabel : warningLabel}\n${item.message}`).join('\n\n'),
          )}>
            {t('plugins.copyDiagnostics', '复制全部消息')}
          </DialogActionButton>
        </div>
      ) : null}
    </DialogFrame>
  );
}
