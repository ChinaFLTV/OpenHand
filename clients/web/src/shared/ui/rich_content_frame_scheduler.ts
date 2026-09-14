import {
  isTranscriptScrollActive,
  scheduleAfterTranscriptScrollSettles,
} from './transcript_scroll_activity';

const IDLE_TIMEOUT_MS = 100;
const FRAME_FALLBACK_MS = 16;

/** HTML 和 Markdown 共用帧预算，取消时立即释放闭包及其消息引用。 */
export class RichContentFrameScheduler {
  private readonly pending = new Set<{ task: () => void }>();
  private draining = false;
  private cancelScrollWait: (() => void) | null = null;

  schedule(task: () => void): () => void {
    const entry = { task };
    this.pending.add(entry);
    if (!this.draining) {
      this.draining = true;
      this.scheduleFrame();
    }
    return () => {
      this.pending.delete(entry);
      if (this.pending.size === 0 && this.cancelScrollWait != null) {
        this.cancelScrollWait();
        this.cancelScrollWait = null;
        this.draining = false;
      }
    };
  }

  private scheduleFrame(allowDuringScroll = false): void {
    const afterFrame = () => {
      if (this.pending.size === 0) {
        this.draining = false;
        return;
      }
      if (!allowDuringScroll && isTranscriptScrollActive()) {
        this.cancelScrollWait = scheduleAfterTranscriptScrollSettles(() => {
          this.cancelScrollWait = null;
          this.scheduleFrame(true);
        });
        return;
      }
      if (typeof requestIdleCallback === 'function') {
        requestIdleCallback(() => this.drain(allowDuringScroll), { timeout: IDLE_TIMEOUT_MS });
      } else {
        this.drain(allowDuringScroll);
      }
    };
    // 仅用空闲回调不能保证逐帧执行：同一帧可能连续触发多个空闲回调。
    if (typeof requestAnimationFrame === 'function') requestAnimationFrame(afterFrame);
    else setTimeout(afterFrame, FRAME_FALLBACK_MS);
  }

  private drain(allowDuringScroll: boolean): void {
    if (!allowDuringScroll && isTranscriptScrollActive()) {
      this.scheduleFrame();
      return;
    }
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
