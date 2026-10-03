const MAX_ENTRIES = 64;
const MAX_SOURCE_CHARACTERS = 512 * 1024;
const MAX_AST_NODES = 24000;
const MAX_ENTRY_NODES = 6000;
const MAX_RENDER_DEPTH = 64;

interface AstNode {
  type?: string;
  value?: string;
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
  if (!parse) return;
  const cacheEnabled = enabled && typeof structuredClone === 'function';
  this.parser = (source, file) => {
    const key = `${math ? '公式' : '标准'}:${source}`;
    const cached = cacheEnabled ? entries.get(key) : undefined;
    if (cached) {
      entries.delete(key);
      entries.set(key, cached);
      return structuredClone(cached.tree);
    }
    const tree = parse(source, file);
    const pending: Array<[AstNode, number]> = [[tree, 0]];
    let nodes = 0;
    while (pending.length > 0) {
      const [node, depth] = pending.pop()!;
      nodes += 1;
      if (depth > MAX_RENDER_DEPTH ||
          nodes + pending.length + (node.children?.length ?? 0) > MAX_ENTRY_NODES) {
        // 超预算时显示完整原文，避免继续构建数千组件；复制与导出保持原消息。
        return { type: 'root', children: [{ type: 'paragraph', children: [{ type: 'text', value: source }] }] };
      }
      if (node.children) {
        for (const child of node.children) pending.push([child, depth + 1]);
      }
    }
    if (!cacheEnabled || source.length > MAX_SOURCE_CHARACTERS) return tree;
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
