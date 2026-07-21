function pad2(value: number): string {
  return String(value).padStart(2, '0');
}

export function formatLocalDateTimeMinute(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

export function formatLocalDateTimeSecond(
  iso: string,
  invalidValue = iso,
): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return invalidValue;
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
}
