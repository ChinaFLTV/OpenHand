const IDLE_TIMEOUT_MS = 100;
const FRAME_FALLBACK_MS = 16;

/** HTML 和 Markdown 共用帧预算，取消时立即释放闭包及其消息引用。 */
export class RichContentFrameScheduler {
  private readonly pending = new Set<{ task: () => void }>();
  private draining = false;

  schedule(task: () => void): () => void {
    const entry = { task };
    this.pending.add(entry);
    if (!this.draining) {
      this.draining = true;
      this.scheduleFrame();
    }
    return () => {
      this.pending.delete(entry);
    };
  }

  private scheduleFrame(): void {
    const afterFrame = () => {
      if (this.pending.size === 0) {
        this.draining = false;
        return;
      }
      // 滚动期间也按空闲预算逐帧推进，避免可见卡片逐张等待滚动结束。
      if (typeof requestIdleCallback === 'function') {
        requestIdleCallback(() => this.drain(), { timeout: IDLE_TIMEOUT_MS });
      } else {
        this.drain();
      }
    };
    // 仅用空闲回调不能保证逐帧执行：同一帧可能连续触发多个空闲回调。
    if (typeof requestAnimationFrame === 'function') requestAnimationFrame(afterFrame);
    else setTimeout(afterFrame, FRAME_FALLBACK_MS);
  }

  private drain(): void {
    const entry = this.pending.values().next().value;
    if (entry) this.pending.delete(entry);
    try {
      entry?.task();
    } finally {
      if (this.pending.size > 0) this.scheduleFrame();
      else this.draining = false;
    }
  }
}

export const richContentFrameScheduler = new RichContentFrameScheduler();
