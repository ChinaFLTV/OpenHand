export interface JsonParseBounds {
  maxCharacters: number;
  maxDepth: number;
  maxContainerItems: number;
  maxNodes: number;
}

export class JsonStructureLimitError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'JsonStructureLimitError';
  }
}

function requireBounds(bounds: JsonParseBounds): void {
  if (!Number.isSafeInteger(bounds.maxCharacters) || bounds.maxCharacters <= 0) {
    throw new RangeError('maxCharacters 必须是正安全整数。');
  }
  if (!Number.isSafeInteger(bounds.maxDepth) || bounds.maxDepth < 0) {
    throw new RangeError('maxDepth 必须是非负安全整数。');
  }
  if (!Number.isSafeInteger(bounds.maxContainerItems) || bounds.maxContainerItems <= 0) {
    throw new RangeError('maxContainerItems 必须是正安全整数。');
  }
  if (!Number.isSafeInteger(bounds.maxNodes) || bounds.maxNodes <= 0) {
    throw new RangeError('maxNodes 必须是正安全整数。');
  }
}

function hasBoundedNesting(text: string, maxDepth: number): boolean {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = 0; index < text.length; index += 1) {
    const code = text.charCodeAt(index);
    if (inString) {
      if (escaped) escaped = false;
      else if (code === 0x5c) escaped = true;
      else if (code === 0x22) inString = false;
      continue;
    }
    if (code === 0x22) inString = true;
    else if (code === 0x7b || code === 0x5b) {
      depth += 1;
      if (depth > maxDepth) return false;
    } else if (code === 0x7d || code === 0x5d) {
      depth -= 1;
    }
  }
  return true;
}

function assertBoundedJsonValue(
  value: unknown,
  { maxContainerItems, maxNodes }: JsonParseBounds,
): void {
  const pending: unknown[] = [value];
  let visitedNodes = 0;
  while (pending.length > 0) {
    const current = pending.pop();
    visitedNodes += 1;
    if (visitedNodes > maxNodes) {
      throw new JsonStructureLimitError('JSON 节点数量超过处理上限。');
    }
    if (
      current == null ||
      typeof current === 'string' ||
      typeof current === 'boolean'
    ) {
      continue;
    }
    if (typeof current === 'number') {
      if (!Number.isFinite(current)) {
        throw new JsonStructureLimitError('JSON 包含非有限数值。');
      }
      continue;
    }
    if (typeof current !== 'object') {
      throw new JsonStructureLimitError('JSON 包含不支持的值。');
    }

    const values = Array.isArray(current)
      ? current
      : Object.values(current as Record<string, unknown>);
    if (values.length > maxContainerItems) {
      throw new JsonStructureLimitError('JSON 容器条目数量超过处理上限。');
    }
    if (values.length + pending.length > maxNodes - visitedNodes) {
      throw new JsonStructureLimitError('JSON 节点数量超过处理上限。');
    }
    for (const child of values) pending.push(child);
  }
}

/** 在解析前后同时限制 JSON 大小、嵌套、容器条目和总节点数。 */
export function parseJsonBounded(text: string, bounds: JsonParseBounds): unknown {
  requireBounds(bounds);
  if (text.length > bounds.maxCharacters) {
    throw new JsonStructureLimitError('JSON 文本长度超过处理上限。');
  }
  if (!hasBoundedNesting(text, bounds.maxDepth)) {
    throw new JsonStructureLimitError('JSON 嵌套层级超过处理上限。');
  }
  const value = JSON.parse(text) as unknown;
  assertBoundedJsonValue(value, bounds);
  return value;
}
