import { t, tNumber } from '../../i18n';
import { decisionFenceLanguageLabel } from './decision';

// 语言名称保留标准标识，界面类型名称随当前语言显示。
const LANGUAGES: Record<string, [string, string]> = {
  json: ['JSON', 'json'], yaml: ['YAML', 'yaml'], yml: ['YAML', 'yaml'],
  javascript: ['JavaScript', 'js'], js: ['JavaScript', 'js'],
  typescript: ['TypeScript', 'ts'], ts: ['TypeScript', 'ts'],
  python: ['Python', 'py'], py: ['Python', 'py'], dart: ['Dart', 'dart'],
  html: ['HTML', 'html'], css: ['CSS', 'css'], sql: ['SQL', 'sql'],
  markdown: ['Markdown', 'md'], md: ['Markdown', 'md'], mermaid: ['Mermaid', 'mmd'],
  diff: ['', 'diff'], patch: ['', 'patch'], shell: ['', 'sh'], bash: ['', 'sh'],
  sh: ['', 'sh'], zsh: ['', 'sh'], plaintext: ['', 'txt'], text: ['', 'txt'], txt: ['', 'txt'],
};

export function codeLanguageLabel(language?: string | null): string {
  const key = language?.trim().toLowerCase() ?? '';
  const known = LANGUAGES[key];
  if (!key || known?.[1] === 'txt') return t('codeBlock.plainText');
  if (known?.[1] === 'sh') return t('codeBlock.shell');
  if (known?.[1] === 'diff' || known?.[1] === 'patch') return t('codeBlock.diffLabel');
  return decisionFenceLanguageLabel(key) ?? known?.[0] ?? language!.trim();
}

export function codeFileExtension(language?: string | null): string {
  return LANGUAGES[language?.trim().toLowerCase() ?? '']?.[1] ?? 'txt';
}

export function codeLineCount(source: string): number {
  let count = 1;
  for (let index = 0; index < source.length; index++) if (source.charCodeAt(index) === 10) count++;
  return count;
}

export function codeLineCountLabel(count: number): string {
  return t(count === 1 ? 'codeBlock.line' : 'codeBlock.lines').replace('{count}', tNumber(count));
}
