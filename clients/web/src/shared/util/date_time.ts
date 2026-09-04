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

const MS_PER_SECOND = 1000;
const MS_PER_MINUTE = 60_000;

export function formatDurationMs(
  milliseconds: number | null | undefined,
  invalidValue = '—',
): string {
  if (milliseconds == null || !Number.isFinite(milliseconds) || milliseconds < 0) {
    return invalidValue;
  }
  if (milliseconds < MS_PER_SECOND) return `${Math.round(milliseconds)} ms`;
  if (milliseconds < MS_PER_MINUTE) {
    const seconds = milliseconds / MS_PER_SECOND;
    return `${seconds.toFixed(seconds < 10 ? 2 : 1)} s`;
  }
  return `${(milliseconds / MS_PER_MINUTE).toFixed(1)} min`;
}

export function formatClockDuration(totalSeconds: number): string {
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) return '00:00';
  const total = Math.floor(totalSeconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const rest = total % 60;
  return hours > 0
    ? `${hours}:${pad2(minutes)}:${pad2(rest)}`
    : `${pad2(minutes)}:${pad2(rest)}`;
}
