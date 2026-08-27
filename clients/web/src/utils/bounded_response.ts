import { ignoreError } from '../shared/util/errors';

interface BoundedResponseBlobOptions {
  maxBytes: number;
  signal?: AbortSignal;
}

type BoundedResponseBodyOptions = BoundedResponseBlobOptions;

interface FetchBlobBoundedOptions extends RequestInit {
  maxBytes: number;
}

class ResponseBodySizeLimitError extends Error {
  readonly maxBytes: number;

  constructor(maxBytes: number) {
    const maxMiB = Math.ceil(maxBytes / (1024 * 1024));
    super(`响应体超过 ${maxMiB} MiB 安全上限。`);
    this.name = 'ResponseBodySizeLimitError';
    this.maxBytes = maxBytes;
  }
}

function requirePositiveByteLimit(maxBytes: number): void {
  if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0) {
    throw new RangeError('maxBytes 必须是正安全整数。');
  }
}

export function cancelResponseBodyQuietly(
  response: Response,
  reason?: unknown,
): void {
  try {
    void response.body?.cancel(reason).catch(ignoreError);
  } catch {
    // 响应流可能已锁定或关闭，清理失败不覆盖原始错误。
  }
}

function abortReason(signal: AbortSignal): unknown {
  return signal.reason ?? new DOMException('操作已取消。', 'AbortError');
}

function declaredResponseBytes(response: Response): number | null {
  const raw = response.headers.get('content-length')?.trim();
  if (!raw || !/^\d+$/.test(raw)) return null;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

async function cancelReaderQuietly(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  reason?: unknown,
): Promise<void> {
  try {
    await reader.cancel(reason);
  } catch {
    // 取消失败不覆盖原始超时或容量错误。
  }
}

async function consumeResponseBodyBounded(
  response: Response,
  { maxBytes, signal }: BoundedResponseBodyOptions,
  onChunk: (chunk: Uint8Array) => void,
): Promise<void> {
  requirePositiveByteLimit(maxBytes);
  const declaredBytes = declaredResponseBytes(response);
  if (declaredBytes != null && declaredBytes > maxBytes) {
    const error = new ResponseBodySizeLimitError(maxBytes);
    cancelResponseBodyQuietly(response, error);
    throw error;
  }

  const body = response.body;
  if (body == null) {
    if (declaredBytes == null || declaredBytes === 0) {
      return;
    }
    throw new Error('响应体数据流不可用。');
  }

  const reader = body.getReader();
  let receivedBytes = 0;
  const handleAbort = () => {
    void cancelReaderQuietly(reader, signal ? abortReason(signal) : undefined);
  };
  signal?.addEventListener('abort', handleAbort, { once: true });
  try {
    if (signal?.aborted) throw abortReason(signal);
    while (true) {
      const part = await reader.read();
      if (signal?.aborted) throw abortReason(signal);
      if (part.done) break;
      const chunk = part.value;
      if (chunk.byteLength > maxBytes - receivedBytes) {
        const error = new ResponseBodySizeLimitError(maxBytes);
        await cancelReaderQuietly(reader, error);
        throw error;
      }
      receivedBytes += chunk.byteLength;
      onChunk(chunk);
    }
  } finally {
    signal?.removeEventListener('abort', handleAbort);
    try {
      reader.releaseLock();
    } catch {
      // 数据流可能已取消或分离。
    }
  }
}

/// 在明确的字节上限内读取完整二进制响应体。
/// 调用方提供的信号必须覆盖完整读取阶段，而不只是响应头阶段。
export async function readResponseBlobBounded(
  response: Response,
  options: BoundedResponseBlobOptions,
): Promise<Blob> {
  const chunks: BlobPart[] = [];
  await consumeResponseBodyBounded(response, options, (chunk) => {
    chunks.push(chunk.slice());
  });
  return new Blob(chunks, {
    type: response.headers.get('content-type') ?? '',
  });
}

/// 请求并在明确的字节上限内读取二进制响应；失败响应会主动释放数据流。
export async function fetchBlobBounded(
  input: RequestInfo | URL,
  { maxBytes, ...init }: FetchBlobBoundedOptions,
): Promise<Blob> {
  requirePositiveByteLimit(maxBytes);
  const response = await fetch(input, init);
  if (!response.ok) {
    const error = new Error(`请求失败（HTTP ${response.status}）`);
    cancelResponseBodyQuietly(response, error);
    throw error;
  }
  return readResponseBlobBounded(response, {
    maxBytes,
    signal: init.signal ?? undefined,
  });
}

/// 在明确的 UTF-8 字节上限内读取文本响应，避免 `response.text()` 无界聚合。
export async function readResponseTextBounded(
  response: Response,
  options: BoundedResponseBodyOptions,
): Promise<string> {
  const decoder = new TextDecoder();
  const parts: string[] = [];
  await consumeResponseBodyBounded(response, options, (chunk) => {
    parts.push(decoder.decode(chunk, { stream: true }));
  });
  parts.push(decoder.decode());
  return parts.join('');
}
