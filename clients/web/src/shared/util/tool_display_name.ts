import { t } from '../../i18n';

/// 翻译内置工具名称；外部工具和自定义标识使用原名。
export function toolDisplayName(name: string): string {
  const normalized = name.trim().toLowerCase();
  const canonical = normalized.startsWith('terminal')
    ? `machine${normalized}`
    : normalized;
  return t(`message.toolName.${canonical}`, name);
}

export function fileMutationLabel(kind: string): string {
  return t(`detail.fileMutation.kind.${kind.toLowerCase()}`, kind);
}
