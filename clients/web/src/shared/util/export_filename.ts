export function normalizeJsonlExportFilename(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) return 'session.jsonl';

  const trailingMatch = trimmed.match(/\.jsonl$/i);
  if (!trailingMatch) return `${trimmed}.jsonl`;

  const suffix = trailingMatch[0];
  let base = trimmed.slice(0, -suffix.length);
  while (/\.jsonl$/i.test(base)) {
    base = base.slice(0, -'.jsonl'.length);
  }
  return `${base || 'session'}${suffix}`;
}

export function jsonlExportPickerSuggestedName(input: string): string {
  const normalized = normalizeJsonlExportFilename(input);
  return normalized.replace(/\.jsonl$/i, '') || 'session';
}
