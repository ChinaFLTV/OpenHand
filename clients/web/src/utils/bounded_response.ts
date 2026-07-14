export interface BoundedResponseBlobOptions {
  maxBytes: number;
  signal?: AbortSignal;
}

export class ResponseBodySizeLimitError extends Error {
  readonly maxBytes: number;

  constructor(maxBytes: number) {
    const maxMiB = Math.ceil(maxBytes / (1024 * 1024));
    super(`Response body exceeds the ${maxMiB} MiB safety limit.`);
    this.name = 'ResponseBodySizeLimitError';
    this.maxBytes = maxBytes;
  }
}

function abortReason(signal: AbortSignal): unknown {
  return signal.reason ?? new DOMException('The operation was aborted.', 'AbortError');
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
    // Cancellation is best-effort; preserve the primary timeout/limit error.
  }
}

/// Reads a complete response body while enforcing an explicit byte ceiling.
/// The caller-provided signal should cover the entire read, not only fetch's
/// response-header phase.
export async function readResponseBlobBounded(
  response: Response,
  { maxBytes, signal }: BoundedResponseBlobOptions,
): Promise<Blob> {
  if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0) {
    throw new RangeError('maxBytes must be a positive safe integer.');
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
    throw new Error('Response body stream is unavailable.');
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
      // The stream may already be cancelled or detached.
    }
  }
  return new Blob(chunks, {
    type: response.headers.get('content-type') ?? '',
  });
}
