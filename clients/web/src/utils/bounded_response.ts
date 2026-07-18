interface BoundedResponseBlobOptions {
  maxBytes: number;
  signal?: AbortSignal;
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

/// 在明确的字节上限内读取完整响应体。
/// 调用方提供的信号必须覆盖完整读取阶段，而不只是响应头阶段。
export async function readResponseBlobBounded(
  response: Response,
  { maxBytes, signal }: BoundedResponseBlobOptions,
): Promise<Blob> {
  if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0) {
    throw new RangeError('maxBytes 必须是正安全整数。');
  }
  const declaredBytes = declaredResponseBytes(response);
  if (declaredBytes != null && declaredBytes > maxBytes) {
    void response.body?.cancel().catch(() => {});
    throw new ResponseBodySizeLimitError(maxBytes);
  }

  const body = response.body;
  if (body == null) {
    if (declaredBytes == null || declaredBytes === 0) {
      return new Blob([], {
        type: response.headers.get('content-type') ?? '',
      });
    }
    throw new Error('响应体数据流不可用。');
  }

  const reader = body.getReader();
  const chunks: BlobPart[] = [];
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
      chunks.push(chunk.slice());
    }
  } finally {
    signal?.removeEventListener('abort', handleAbort);
    try {
      reader.releaseLock();
    } catch {
      // 数据流可能已取消或分离。
    }
  }
  return new Blob(chunks, {
    type: response.headers.get('content-type') ?? '',
  });
}
