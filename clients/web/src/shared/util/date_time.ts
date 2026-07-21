function pad2(value: number): string {
  return String(value).padStart(2, '0');
}

function localDateOrNull(iso: string | null | undefined): Date | null {
  if (!iso) return null;
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function formatLocalDateTimeMinute(iso: string): string {
  const date = localDateOrNull(iso);
  if (!date) return iso;
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

export function formatLocalDateTimeSecond(
  iso: string | null | undefined,
  invalidValue = iso ?? '—',
): string {
  const date = localDateOrNull(iso);
  if (!date) return invalidValue;
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
}

export function formatLocalTimeSecond(
  iso: string | null | undefined,
  invalidValue = iso ?? '—',
): string {
  const date = localDateOrNull(iso);
  if (!date) return invalidValue;
  return `${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
}
