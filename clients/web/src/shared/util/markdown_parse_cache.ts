const MAX_ENTRIES = 64;
const MAX_SOURCE_CHARACTERS = 512 * 1024;
const MAX_AST_NODES = 24000;
const MAX_ENTRY_NODES = 6000;

interface AstNode {
  children?: AstNode[];
}

type Parser = (source: string, file: unknown) => AstNode;
interface CacheEntry {
  tree: AstNode;
  nodes: number;
}

const entries = new Map<string, CacheEntry>();
let sourceCharacters = 0;
let astNodes = 0;

/** 缓存解析结果的独立副本，插件修改语法树时不会污染其他消息。 */
export function remarkCachedParse(
  this: { parser?: Parser },
  { enabled, math }: { enabled: boolean; math: boolean },
): void {
  const parse = this.parser;
  if (!enabled || !parse || typeof structuredClone !== 'function') return;
  this.parser = (source, file) => {
    const key = `${math ? '公式' : '标准'}:${source}`;
    const cached = entries.get(key);
    if (cached) {
      entries.delete(key);
      entries.set(key, cached);
      return structuredClone(cached.tree);
    }
    const tree = parse(source, file);
    if (source.length > MAX_SOURCE_CHARACTERS) return tree;
    const pending = [tree];
    let nodes = 0;
    while (pending.length > 0) {
      const node = pending.pop()!;
      nodes += 1;
      if (nodes > MAX_ENTRY_NODES) return tree;
      if (node.children) {
        // 逐个压栈，避免宽表格的子节点突破函数参数上限。
        for (const child of node.children) pending.push(child);
      }
    }
    entries.set(key, { tree: structuredClone(tree), nodes });
    sourceCharacters += key.length;
    astNodes += nodes;
    while (entries.size > MAX_ENTRIES || sourceCharacters > MAX_SOURCE_CHARACTERS || astNodes > MAX_AST_NODES) {
      const oldest = entries.keys().next().value!;
      const removed = entries.get(oldest)!;
      entries.delete(oldest);
      sourceCharacters -= oldest.length;
      astNodes -= removed.nodes;
    }
    return tree;
  };
}
