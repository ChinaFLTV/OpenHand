import type { SessionEventSnapshot } from '../../api/session_events';
import { messageWindowsEquivalentForRender } from './session_message_window';
import { jsonValuesEqual } from './value';

/** 仅忽略服务端发送时间；审批、窗口和运行状态变化均须交给页面。 */
export function sessionSnapshotsEquivalent(
  previous: SessionEventSnapshot | null,
  next: SessionEventSnapshot,
): boolean {
  if (previous === next) return true;
  if (!previous ||
    previous.send_phase !== next.send_phase ||
    previous.can_stop !== next.can_stop ||
    previous.last_error !== next.last_error ||
    previous.messages.length !== next.messages.length
  ) return false;
  if (!messageWindowsEquivalentForRender(previous.messages, next.messages)) return false;
  return jsonValuesEqual(previous.message_window, next.message_window) &&
    jsonValuesEqual(previous.pending_write_approval, next.pending_write_approval) &&
    jsonValuesEqual(previous.effective_stream_throttle, next.effective_stream_throttle) &&
    jsonValuesEqual(previous.session, next.session);
}
