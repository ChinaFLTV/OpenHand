/** 按条目数和 UTF-16 总长度双重限制；原文作键避免摘要碰撞串卡。 */
export class BoundedTextCache {
  private readonly entries = new Map<string, string>();
  private characters = 0;

  constructor(private readonly maxEntries: number, private readonly maxCharacters: number) {
    for (const [name, value] of [['maxEntries', maxEntries], ['maxCharacters', maxCharacters]] as const) {
      if (!Number.isSafeInteger(value) || value < 0) {
        throw new RangeError(`${name} 必须为非负安全整数。`);
      }
    }
  }

  get(key: string): string | undefined {
    const value = this.entries.get(key);
    if (value !== undefined) {
      this.entries.delete(key);
      this.entries.set(key, value);
    }
    return value;
  }

  set(key: string, value: string): void {
    const previous = this.entries.get(key);
    if (previous !== undefined) {
      this.characters -= key.length + previous.length;
      this.entries.delete(key);
    }
    const cost = key.length + value.length;
    if (cost > this.maxCharacters || this.maxEntries <= 0) return;
    this.entries.set(key, value);
    this.characters += cost;
    while (this.entries.size > this.maxEntries || this.characters > this.maxCharacters) {
      const [oldestKey, oldestValue] = this.entries.entries().next().value!;
      this.entries.delete(oldestKey);
      this.characters -= oldestKey.length + oldestValue.length;
    }
  }
}
