export function basenameFromPath(input: string): string {
  const path = input.trim();
  if (!path) return '';
  const index = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return index >= 0 ? path.slice(index + 1) : path;
}
